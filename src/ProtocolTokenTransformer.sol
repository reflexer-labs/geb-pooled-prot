pragma solidity 0.6.7;

import "ds-token/token.sol";

contract ProtocolTokenTransformer {
    // --- Auth ---
    mapping (address => uint) public authorizedAccounts;
    /**
     * @notice Add auth to an account
     * @param account Account to add auth to
     */
    function addAuthorization(address account) virtual external isAuthorized {
        authorizedAccounts[account] = 1;
        emit AddAuthorization(account);
    }
    /**
     * @notice Remove auth from an account
     * @param account Account to remove auth from
     */
    function removeAuthorization(address account) virtual external isAuthorized {
        authorizedAccounts[account] = 0;
        emit RemoveAuthorization(account);
    }
    /**
    * @notice Checks whether msg.sender can call an authed function
    **/
    modifier isAuthorized {
        require(authorizedAccounts[msg.sender] == 1, "ProtocolTokenTransformer/account-not-authorized");
        _;
    }

    // --- Variables ---
    // Flag that allows/blocks joining
    bool    public canJoin;
    // The token being deposited in the transformer
    DSToken public ancestor;
    // The token being backed by ancestor tokens
    DSToken public descendant;

    // --- Events ---
    event AddAuthorization(address account);
    event RemoveAuthorization(address account);
    event ToggleJoin(bool canJoin);
    event Join(address indexed account, uint256 price, uint256 amount);
    event Exit(address indexed account, uint256 price, uint256 amount);

    constructor(address ancestor_, address descendant_) public {
        authorizedAccounts[msg.sender] = 1;
        canJoin                        = true;

        ancestor                       = DSToken(ancestor_);
        descendant                     = DSToken(descendant_);

        require(ancestor.decimals() == 18, "ProtocolTokenTransformer/ancestor-decimal-mismatch");
        require(descendant.decimals() == 18, "ProtocolTokenTransformer/descendant-decimal-mismatch");

        emit AddAuthorization(msg.sender);
    }

    // --- Math ---
    uint256 public constant RAY = 10 ** 27;
    uint256 public constant WAD = 10 ** 18;

    function multiply(uint x, uint y) internal pure returns (uint z) {
        require(y == 0 || (z = x * y) / y == x, "uint-uint-mul-overflow");
    }
    function wdivide(uint x, uint y) public pure returns (uint z) {
        require(y > 0, "uint-uint-wdiv-by-zero");
        z = multiply(x, WAD) / y;
    }
    function wmultiply(uint x, uint y) internal pure returns (uint z) {
        z = multiply(x, y) / WAD;
    }

    // --- Administration ---
    function toggleJoin() external isAuthorized {
        canJoin = !canJoin;
        emit ToggleJoin(canJoin);
    }

    // --- Getters ---
    function depositedAncestor() public view returns (uint256) {
        return ancestor.balanceOf(address(this));
    }
    function ancestorPerDescendant() public view returns (uint256) {
        return descendant.totalSupply() == 0 ? WAD : wdivide(depositedAncestor(), descendant.totalSupply());
    }
    function descendantPerAncestor() public view returns (uint256) {
        return descendant.totalSupply() == 0 ? WAD : wdivide(descendant.totalSupply(), depositedAncestor());
    }
    function joinPrice(uint256 wad) public view returns (uint256) {
        return wmultiply(wad, descendantPerAncestor());
    }
    function exitPrice(uint256 wad) public view returns (uint256) {
        return wmultiply(wad, ancestorPerDescendant());
    }

    // --- Core Logic ---
    function join(uint256 wad) public {
        require(canJoin);
        require(wad > 0, "ProtocolTokenTransformer/null-ancestor-to-join");

        uint256 price = joinPrice(wad);
        require(price > 0, "ProtocolTokenTransformer/null-join-price");

        require(ancestor.transferFrom(msg.sender, address(this), wad), "ProtocolTokenTransformer/could-not-transfer-ancestor");
        descendant.mint(msg.sender, price);
        emit Join(msg.sender, price, wad);
    }
    function exit(uint256 wad) public {
        require(wad > 0, "ProtocolTokenTransformer/null-descendant-to-burn");

        uint256 price = exitPrice(wad);
        require(ancestor.transfer(msg.sender, price), "ProtocolTokenTransformer/could-not-transfer-ancestor");

        descendant.burn(msg.sender, wad);
        emit Exit(msg.sender, price, wad);
    }
}

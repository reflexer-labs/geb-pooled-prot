pragma solidity 0.6.7;

import "ds-token/token.sol";

contract TokenTransformer {
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
        require(authorizedAccounts[msg.sender] == 1, "TokenTransformer/account-not-authorized");
        _;
    }

    // --- Structs ---
    struct ExitWindow {
        // Start time when the exit can happen
        uint256 start;
        // Exit window deadline
        uint256 end;
    }

    // --- Variables ---
    // Flag that allows/blocks joining
    bool    public canJoin;
    // The current delay enforced on an exit
    uint256 public exitDelay;
    // Time during which an address can exit without requesting a new window
    uint256 public exitWindow;
    // The token being deposited in the transformer
    DSToken public ancestor;
    // The token being backed by ancestor tokens
    DSToken public descendant;
    // Exit data
    mapping(address => ExitWindow) public exitWindows;

    // Max delay that can be enforced for an exit
    uint256 public immutable MAX_DELAY;
    // Minimum exit window during which an address can exit without waiting again for another window
    uint256 public immutable MIN_EXIT_WINDOW;
    // Max exit window during which an address can exit without waiting again for another window
    uint256 public immutable MAX_EXIT_WINDOW;

    // --- Events ---
    event AddAuthorization(address account);
    event RemoveAuthorization(address account);
    event ModifyParameters(bytes32 indexed parameter, uint256 data);
    event ToggleJoin(bool canJoin);
    event RequestExit(address indexed account, uint256 start, uint256 end);
    event Join(address indexed account, uint256 price, uint256 amount);
    event Exit(address indexed account, uint256 price, uint256 amount);

    constructor(
      address ancestor_,
      address descendant_,
      uint256 maxDelay_,
      uint256 minExitWindow_,
      uint256 maxExitWindow_,
      uint256 exitDelay_,
      uint256 exitWindow_
    ) public {
        require(maxDelay_ > 0, "TokenTransformer/null-max-delay");
        require(both(maxExitWindow_ > 0, maxExitWindow_ > minExitWindow_), "TokenTransformer/invalid-max-exit-window");
        require(minExitWindow_ > 0, "TokenTransformer/invalid-min-exit-window");
        require(exitDelay_ <= maxDelay_, "TokenTransformer/invalid-exit-delay");
        require(both(exitWindow_ >= minExitWindow_, exitWindow_ <= maxExitWindow_), "TokenTransformer/invalid-exit-window");

        authorizedAccounts[msg.sender] = 1;
        canJoin                        = true;

        MAX_DELAY                      = maxDelay_;
        MIN_EXIT_WINDOW                = minExitWindow_;
        MAX_EXIT_WINDOW                = maxExitWindow_;

        exitDelay                      = exitDelay_;
        exitWindow                     = exitWindow_;

        ancestor                       = DSToken(ancestor_);
        descendant                     = DSToken(descendant_);

        require(ancestor.decimals() == 18, "TokenTransformer/ancestor-decimal-mismatch");
        require(descendant.decimals() == 18, "TokenTransformer/descendant-decimal-mismatch");

        emit AddAuthorization(msg.sender);
    }

    // --- Boolean Logic ---
    function both(bool x, bool y) internal pure returns (bool z) {
        assembly{ z := and(x, y)}
    }

    // --- Math ---
    uint256 public constant WAD = 10 ** 18;

    function addition(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require((z = x + y) >= x, "TokenTransformer/add-overflow");
    }
    function multiply(uint x, uint y) internal pure returns (uint z) {
        require(y == 0 || (z = x * y) / y == x, "TokenTransformer/mul-overflow");
    }
    function wdivide(uint x, uint y) internal pure returns (uint z) {
        require(y > 0, "TokenTransformer/wdiv-by-zero");
        z = multiply(x, WAD) / y;
    }
    function wmultiply(uint x, uint y) internal pure returns (uint z) {
        z = multiply(x, y) / WAD;
    }

    // --- Administration ---
    /*
    * @notify Switch between allowing and disallowing joins
    */
    function toggleJoin() external isAuthorized {
        canJoin = !canJoin;
        emit ToggleJoin(canJoin);
    }
    /*
    * @notify Modify a uint256 parameter
    * @param parameter The name of the parameter to modify
    * @param data New value for the parameter
    */
    function modifyParameters(bytes32 parameter, uint256 data) external isAuthorized {
        if (parameter == "exitDelay") {
          require(data <= MAX_DELAY, "TokenTransformer/invalid-exit-delay");
          exitDelay = data;
        }
        else if (parameter == "exitWindow") {
          require(both(data >= MIN_EXIT_WINDOW, data <= MAX_EXIT_WINDOW), "TokenTransformer/invalid-exit-window");
          exitWindow = data;
        }
        else revert("TokenTransformer/modify-unrecognized-param");
        emit ModifyParameters(parameter, data);
    }

    // --- Getters ---
    /*
    * @notify Return the ancestor token balance for this contract
    */
    function depositedAncestor() public view returns (uint256) {
        return ancestor.balanceOf(address(this));
    }
    /*
    * @notify Returns how many ancestor tokens are offered for one descendant token
    */
    function ancestorPerDescendant() public view returns (uint256) {
        return descendant.totalSupply() == 0 ? WAD : wdivide(depositedAncestor(), descendant.totalSupply());
    }
    /*
    * @notify Returns how many descendant tokens are offered for one ancestor token
    */
    function descendantPerAncestor() public view returns (uint256) {
        return descendant.totalSupply() == 0 ? WAD : wdivide(descendant.totalSupply(), depositedAncestor());
    }
    /*
    * @notify Given a custom amount of ancestor tokens, it returns the corresponding amount of descendant tokens to mint when someone joins
    * @param wad The amount of ancestor tokens to compute the descendant tokens for
    */
    function joinPrice(uint256 wad) public view returns (uint256) {
        return wmultiply(wad, descendantPerAncestor());
    }
    /*
    * @notify Given a custom amount of descendant tokens, it returns the corresponding amount of ancestor tokens to send when someone exits
    * @param wad The amount of descendant tokens to compute the ancestor tokens for
    */
    function exitPrice(uint256 wad) public view returns (uint256) {
        return wmultiply(wad, ancestorPerDescendant());
    }

    // --- Core Logic ---
    /*
    * @notify Join ancestor tokens in exchange for descendant tokens
    * @param wad The amount of ancestor tokens to join
    */
    function join(uint256 wad) public {
        require(canJoin);
        require(wad > 0, "TokenTransformer/null-ancestor-to-join");

        uint256 price = joinPrice(wad);
        require(price > 0, "TokenTransformer/null-join-price");

        require(ancestor.transferFrom(msg.sender, address(this), wad), "TokenTransformer/could-not-transfer-ancestor");
        descendant.mint(msg.sender, price);
        emit Join(msg.sender, price, wad);
    }
    /*
    * @notice Request a new exit window during which you can burn descendant tokens in exchange for ancestor tokens
    */
    function requestExit() public {
        require(now > exitWindows[msg.sender].end, "TokenTransformer/ongoing-request");
        exitWindows[msg.sender].start = addition(now, exitDelay);
        exitWindows[msg.sender].end   = addition(exitWindows[msg.sender].start, exitWindow);
        emit RequestExit(msg.sender, exitWindows[msg.sender].start, exitWindows[msg.sender].end);
    }
    /*
    * @notify Burn descendant tokens in exchange for getting ancestor tokens from this contract
    * @param wad The amount of descendant tokens to exit/burn
    */
    function exit(uint256 wad) public {
        require(wad > 0, "TokenTransformer/null-descendant-to-burn");
        require(both(both(now >= exitWindows[msg.sender].start, now <= exitWindows[msg.sender].end), exitWindows[msg.sender].end > 0), "TokenTransformer/not-in-window");

        uint256 price = exitPrice(wad);

        require(ancestor.transfer(msg.sender, price), "TokenTransformer/could-not-transfer-ancestor");
        descendant.burn(msg.sender, wad);
        emit Exit(msg.sender, price, wad);
    }
}

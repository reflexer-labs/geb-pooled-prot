pragma solidity 0.6.7;

import "ds-token/token.sol";

contract ProtocolTokenTransformer {
    // --- Variables ---
    DSToken public ancestor;
    DSToken public descendant;

    constructor(address ancestor_, address descendant_) public {
        ancestor   = DSToken(ancestor_);
        descendant = DSToken(descendant_);
    }

    // --- Math ---
    uint256 public constant RAY = 10 ** 27;
    uint256 public constant WAD = 10 ** 18;

    function multiply(uint x, uint y) internal pure returns (uint z) {
        require(y == 0 || (z = x * y) / y == x, "uint-uint-mul-overflow");
    }
    function rmultiply(uint x, uint y) internal pure returns (uint z) {
        z = multiply(x, y) / RAY;
    }
    function rdivide(uint x, uint y) internal pure returns (uint z) {
        require(y > 0, "uint-uint-rdiv-by-zero")
        z = multiply(x, RAY) / y;
    }
    function wmultiply(uint x, uint y) internal pure returns (uint z) {
        z = multiply(x, y) / WAD;
    }

    // --- Getters ---
    function depositedOriginal() public view returns (uint256) {
        return ancestor.balanceOf(this);
    }
    function ancestorPerDescendant() public view returns (uint256) {
        return descendant.totalSupply() == 0 ? RAY : rdivide(depositedOriginal(), descendant.totalSupply());
    }
    function joinPrice(uint256 wad) public view returns (uint256) {
        return rmultiply(wad, depositedOriginal());
    }
    function exitPrice(uint256 wad) public view returns (uint256) {
        return rmultiply(wad, wmultiply(depositedOriginal(), WAD));
    }

    // --- Core Logic ---
    function join(uint wad) public {
        require(canJoin);
        require(joinPrice(wad) > 0);
        require(ancestor.transferFrom(msg.sender, address(this), joinPrice(wad)));
        descendant.mint(msg.sender, wad);
    }
    function exit(uint wad) public {
        require(ancestor.transfer(msg.sender, exitPrice(wad)));
        descendant.burn(msg.sender, wad);
    }
}

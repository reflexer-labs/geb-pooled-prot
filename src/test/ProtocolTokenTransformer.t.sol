pragma solidity 0.6.7;

import "ds-test/test.sol";
import {DSAuthority} from "ds-auth/auth.sol";
import {DSDelegateToken} from "ds-token/delegate.sol";
import {ProtocolTokenAuthority} from "geb-protocol-token-authority/ProtocolTokenAuthority.sol";

import "../ProtocolTokenTransformer.sol";

abstract contract Hevm {
    function warp(uint256) virtual public;
}

contract ProtocolTokenTransformerTest is DSTest {
    Hevm hevm;

    DSDelegateToken ancestor;
    DSDelegateToken descendant;

    ProtocolTokenAuthority authority;

    ProtocolTokenTransformer transformer;

    uint256 startTime        = 1577836800;
    uint256 initAmountToMint = 100E18;

    uint256 public constant RAY = 10 ** 27;
    uint256 public constant WAD = 10 ** 18;

    function setUp() public {
        hevm = Hevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
        hevm.warp(startTime);

        ancestor    = new DSDelegateToken("ANC", "ANC");
        descendant  = new DSDelegateToken("DES", "DES");

        authority   = new ProtocolTokenAuthority();
        transformer = new ProtocolTokenTransformer(address(ancestor), address(descendant));

        descendant.setAuthority(DSAuthority(address(authority)));
        descendant.setOwner(address(transformer));

        ancestor.mint(address(this), initAmountToMint);
        ancestor.approve(address(transformer), uint(-1));

        descendant.approve(address(transformer), uint(-1));
    }

    function test_setup() public {
        assertTrue(transformer.canJoin());
        assertEq(transformer.authorizedAccounts(address(this)), 1);
        assertEq(address(transformer.ancestor()), address(ancestor));
        assertEq(address(transformer.descendant()), address(descendant));
    }
    function test_getters_no_interaction() public {
        assertEq(transformer.depositedAncestor(), 0);
        assertEq(transformer.ancestorPerDescendant(), WAD);
        assertEq(transformer.joinPrice(WAD), WAD);
        assertEq(transformer.exitPrice(WAD), WAD);
    }
    function test_join() public {
        assertEq(transformer.ancestorPerDescendant(), WAD);
        assertEq(transformer.joinPrice(WAD), WAD);

        transformer.join(WAD);

        assertEq(descendant.totalSupply(), WAD);
        assertEq(transformer.depositedAncestor(), WAD);
        assertEq(transformer.ancestorPerDescendant(), WAD);
        assertEq(transformer.descendantPerAncestor(), WAD);
        assertEq(transformer.joinPrice(WAD), WAD);
        assertEq(transformer.exitPrice(WAD), WAD);
    }
    function test_exit_some() public {
        transformer.join(WAD);
        transformer.exit(WAD / 2);

        assertEq(descendant.totalSupply(), WAD / 2);
        assertEq(transformer.depositedAncestor(), WAD / 2);
        assertEq(transformer.ancestorPerDescendant(), WAD);
        assertEq(transformer.descendantPerAncestor(), WAD);
        assertEq(transformer.joinPrice(WAD), WAD);
        assertEq(transformer.exitPrice(WAD), WAD);
    }
    function test_exit_all() public {
        transformer.join(WAD);
        transformer.exit(WAD);

        assertEq(descendant.totalSupply(), 0);
        assertEq(transformer.depositedAncestor(), 0);
        assertEq(transformer.ancestorPerDescendant(), WAD);
        assertEq(transformer.descendantPerAncestor(), WAD);
        assertEq(transformer.joinPrice(WAD), WAD);
        assertEq(transformer.exitPrice(WAD), WAD);
    }
    function test_join_exit_prefunded() public {
        ancestor.transfer(address(transformer), WAD);
        assertEq(descendant.totalSupply(), 0);
        assertEq(transformer.depositedAncestor(), WAD);
        assertEq(transformer.ancestorPerDescendant(), WAD);
        assertEq(transformer.descendantPerAncestor(), WAD);
        assertEq(transformer.joinPrice(WAD), WAD);
        assertEq(transformer.exitPrice(WAD), WAD);

        transformer.join(WAD);
        assertEq(ancestor.balanceOf(address(this)), initAmountToMint - 2E18);
        assertEq(descendant.totalSupply(), WAD);
        assertEq(transformer.depositedAncestor(), WAD * 2);
        assertEq(transformer.ancestorPerDescendant(), WAD * 2);
        assertEq(transformer.descendantPerAncestor(), WAD / 2);
        assertEq(transformer.joinPrice(WAD), WAD / 2);
        assertEq(transformer.exitPrice(WAD), WAD * 2);

        transformer.exit(WAD);
        assertEq(ancestor.balanceOf(address(this)), initAmountToMint);
        assertEq(descendant.totalSupply(), 0);
        assertEq(transformer.depositedAncestor(), 0);
        assertEq(transformer.ancestorPerDescendant(), WAD);
        assertEq(transformer.descendantPerAncestor(), WAD);
        assertEq(transformer.joinPrice(WAD), WAD);
        assertEq(transformer.exitPrice(WAD), WAD);
    }
    function testFail_mint_descendant_join() public {
        descendant.mint(address(this), 50E18);
        transformer.join(WAD);
    }
    function test_join_mint_descendant_exit() public {
        transformer.join(WAD);
        descendant.mint(address(this), 49E18);
        transformer.exit(25E18);

        assertEq(descendant.totalSupply(), 25E18);
        assertEq(transformer.depositedAncestor(), WAD / 2);
        assertEq(transformer.ancestorPerDescendant(), WAD / 50);
        assertEq(transformer.descendantPerAncestor(), WAD * 50);
        assertEq(transformer.joinPrice(WAD), WAD * 50);
        assertEq(transformer.exitPrice(WAD), WAD / 50);
    }
    function test_join_tiny_amount_exit() public {
        transformer.join(1);
        transformer.exit(1);

        assertEq(descendant.totalSupply(), 0);
        assertEq(transformer.depositedAncestor(), 0);
        assertEq(transformer.ancestorPerDescendant(), WAD);
        assertEq(transformer.descendantPerAncestor(), WAD);
        assertEq(transformer.joinPrice(WAD), WAD);
        assertEq(transformer.exitPrice(WAD), WAD);
    }
    function test_join_exit_tiny_amount() public {
        transformer.join(WAD);
        transformer.exit(1);

        assertEq(descendant.totalSupply(), WAD - 1);
        assertEq(transformer.depositedAncestor(), WAD - 1);
        assertEq(transformer.ancestorPerDescendant(), WAD);
        assertEq(transformer.descendantPerAncestor(), WAD);
        assertEq(transformer.joinPrice(WAD), WAD);
        assertEq(transformer.exitPrice(WAD), WAD);
    }
    function test_join_descendant_large_mint_exit() public {
        transformer.join(WAD);
        descendant.mint(address(this), RAY * WAD);

        // Checks
        assertEq(descendant.totalSupply(), RAY * WAD + WAD);
        assertEq(transformer.depositedAncestor(), WAD);
        assertEq(transformer.ancestorPerDescendant(), 0);
        assertEq(transformer.descendantPerAncestor(), RAY * WAD + WAD);
        assertEq(transformer.joinPrice(WAD), RAY * WAD + WAD);
        assertEq(transformer.exitPrice(WAD), 0);

        // Exit (will not get any ancestor coins)
        transformer.exit(WAD);

        // Checks
        assertEq(descendant.totalSupply(), RAY * WAD);
        assertEq(transformer.depositedAncestor(), WAD);
        assertEq(transformer.ancestorPerDescendant(), 0);
        assertEq(transformer.descendantPerAncestor(), RAY * WAD);
        assertEq(transformer.joinPrice(WAD), RAY * WAD);
        assertEq(transformer.exitPrice(WAD), 0);
    }
    function test_join_descendant_mint_partial_exit() public {
        transformer.join(WAD);
        descendant.mint(address(this), WAD);

        uint256 oldDescendantBalance = descendant.balanceOf(address(this));
        transformer.join(WAD);
        assertEq(ancestor.balanceOf(address(this)), initAmountToMint - 2E18);

        transformer.exit(descendant.balanceOf(address(this)) - oldDescendantBalance);
        assertEq(ancestor.balanceOf(address(this)), initAmountToMint - 1E18);
    }
    function testFail_join_cannot_join() public {
        transformer.toggleJoin();
        transformer.join(WAD);
    }
}

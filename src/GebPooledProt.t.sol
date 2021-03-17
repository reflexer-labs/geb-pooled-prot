pragma solidity ^0.6.7;

import "ds-test/test.sol";

import "./GebPooledProt.sol";

contract GebPooledProtTest is DSTest {
    GebPooledProt prot;

    function setUp() public {
        prot = new GebPooledProt();
    }

    function testFail_basic_sanity() public {
        assertTrue(false);
    }

    function test_basic_sanity() public {
        assertTrue(true);
    }
}

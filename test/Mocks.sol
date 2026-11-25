// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

/// Stand-in for the Reactive callback proxy (origin side): no debt.
contract MockProxy {
    function debt(address) external pure returns (uint256) { return 0; }
    receive() external payable {}
}

/// Stand-in for the Reactive system contract at 0x8888...: records calls.
contract MockSystem {
    struct Cb { uint256 chainId; address recipient; uint64 gasLimit; bytes payload; }
    uint256 public subscriptions;
    Cb[] public cbs;
    function debt(address) external pure returns (uint256) { return 0; }
    function subscribe(uint256, address, uint256, uint256, uint256, uint256) external { subscriptions++; }
    function requestCallbackV_1_0(Cb calldata c) external { cbs.push(c); }
    function cbCount() external view returns (uint256) { return cbs.length; }
    function payloadAt(uint256 i) external view returns (bytes memory) { return cbs[i].payload; }
    receive() external payable {}
}

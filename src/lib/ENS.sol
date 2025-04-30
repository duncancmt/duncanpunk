// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC165} from "@forge-std/interfaces/IERC165.sol";

import {ERC165Checker} from "./ERC165Checker.sol";

interface Resolver is IERC165 {
    function addr(bytes32 node) external view returns (address);

    function name(bytes32 node) external view returns (string memory);
}

interface Registry {
    function resolver(bytes32 node) external view returns (Resolver);
}

library ENS {
    using ERC165Checker for address;

    Registry private constant _REGISTRY = Registry(0x00000000000C2E074eC69A0dFb2997BA6C7d2e1e);
    bytes32 private constant _ETH_NODE = 0x93cdeb708b7545dc668eb9280176169d1c33cfd8ed6f04690a0bcc88a93fc4ae; // namehash of "eth"
    bytes32 private constant _REVERSE_NODE = 0x91d1777781884d03a6757a803996e38de2a42967fb37eeaca72729271025a9e2; // namehash of "addr.reverse"

    error ENSRoot();
    error NoResolver(bytes32 node);
    error NoRecord(bytes32 node, address resolver);

    function toAddr(bytes32 node) internal view returns (address result) {
        if (node == bytes32(0)) {
            assembly ("memory-safe") {
                mstore(0x00, 0xca1e7dfd) // selector for `ENSRoot()`
                revert(0x1c, 0x04)
            }
        }
        Resolver resolver = _REGISTRY.resolver(node);
        if (!address(resolver).supportsInterface(Resolver.addr.selector)) {
            assembly ("memory-safe") {
                mstore(0x00, 0xe1e6050c) // selector for `NoResolver(bytes32)`
                mstore(0x20, node)
                revert(0x1c, 0x24)
            }
        }
        result = resolver.addr(node);
        if (result == address(0)) {
            assembly ("memory-safe") {
                mstore(0x00, 0xce5df214) // selector for `NoRecord(bytes32,address)`
                mstore(0x20, node)
                mstore(0x40, and(0xffffffffffffffffffffffffffffffffffffffff, resolver))
                revert(0x1c, 0x44)
            }
        }
    }

    // returns namehash of hex(addr).addr.reverse
    // (e.g. "112234455c3a32fd11230c42e7bccd4a84e02010.addr.reverse")
    function reverseNode(address addr) internal pure returns (bytes32 node) {
        assembly ("memory-safe") {
            for {
                let i := 0x28
                let lookup := 0x3031323334353637383961626364656600000000000000000000000000000000
            } i {} {
                i := sub(i, 1)
                mstore8(i, byte(and(addr, 0x0f), lookup))
                addr := shr(4, addr)
                i := sub(i, 1)
                mstore8(i, byte(and(addr, 0x0f), lookup))
                addr := shr(4, addr)
            }
            mstore(0x20, keccak256(0x00, 0x28))
            mstore(0x00, _REVERSE_NODE)
            node := keccak256(0x00, 0x40)
        }
    }

    // check that `name` is part of the *.eth hierarchy and is non-confusable;
    // namehash it
    function _nameHash(string memory name) private pure returns (bytes32 node) {
        // This is written in Yul because memory string slicing doesn't work in
        // Solidity
        assembly ("memory-safe") {
            let i := add(name, mload(name))
            if eq(and(mload(i), 0xffffffff), 0x2e657468) {
                // ".eth"
                node := 1
                mstore(0x00, _ETH_NODE)
                i := sub(i, 4)
                let j := i
                let prevNonHyphen

                // *.eth names with less than 3 characters in the 2ld are invalid
                for { let end := sub(i, 3) } and(node, gt(j, end)) { j := sub(j, 1) } {
                    let c := and(mload(j), 0xff)
                    // check if `j` is the boundary of a component (`.`)
                    switch eq(c, 0x2e)
                    case 0 {
                        // `-` is treated specially to forbid punycode and leading/trailing `-`
                        switch eq(c, 0x2d)
                        case 0 {
                            // check that `c` is in [-0-9a-z]
                            switch or(and(gt(c, 0x2f), lt(c, 0x3a)), and(gt(c, 0x60), lt(c, 0x7b)))
                            case 0 { node := 0 }
                            default { prevNonHyphen := 1 }
                        }
                        default {
                            // forbid `--` (punycode) and `-` at the end of a component
                            switch prevNonHyphen
                            case 0 { node := 0 }
                            default { prevNonHyphen := 0 }
                        }
                    }
                    default {
                        // forbid `.` in position -7 through -5 of the name
                        node := 0
                    }
                }

                // subsequent components of the name are only required to be nonempty
                for {} and(node, gt(j, name)) { j := sub(j, 1) } {
                    let c := and(mload(j), 0xff)
                    // check if `j` is the boundary of a component (`.`)
                    switch eq(c, 0x2e)
                    case 0 {
                        // `-` is treated specially to forbid punycode and leading/trailing `-`
                        switch eq(c, 0x2d)
                        case 0 {
                            // check that `c` is in [-0-9a-z]
                            switch or(and(gt(c, 0x2f), lt(c, 0x3a)), and(gt(c, 0x60), lt(c, 0x7b)))
                            case 0 { node := 0 }
                            default { prevNonHyphen := 1 }
                        }
                        default {
                            // forbid `--` (punycode) and `-` at the end of a component
                            switch prevNonHyphen
                            case 0 { node := 0 }
                            default { prevNonHyphen := 0 }
                        }
                    }
                    default {
                        // forbid empty and `-` at the beginning of a component
                        switch and(prevNonHyphen, iszero(eq(j, i)))
                        case 0 { node := 0 }
                        default {
                            // namehash
                            mstore(0x20, keccak256(add(j, 0x20), sub(i, j)))
                            mstore(0x00, keccak256(0x00, 0x40))

                            i := sub(j, 1)
                            prevNonHyphen := 0
                        }
                    }
                }

                // namehash the final component
                if node {
                    switch and(prevNonHyphen, iszero(eq(j, i)))
                    case 0 { node := 0 }
                    default {
                        mstore(0x20, keccak256(add(j, 0x20), sub(i, j)))
                        node := keccak256(0x00, 0x40)
                    }
                }
            }
        }
    }

    function toNode(string memory name) internal pure returns (bytes32 node) {
        node = _nameHash(name);
        require(node != bytes32(0));
    }

    error NoReverseResolver(address addr);
    error NoReverseRecord(address addr, address resolver);
    error ReverseForwardMismatch(address addr, bytes32 node, address forward);

    function toNode(address addr) internal view returns (bytes32 node, string memory name) {
        // get the address's reverse name and namehash it
        node = reverseNode(addr);

        // get the name that is set as the reverse record for the node
        {
            Resolver resolver = _REGISTRY.resolver(node);
            // The default reverse resolver doesn't support ERC165, in opposition to
            // the standard
            if (!address(resolver).supportsInterface(Resolver.name.selector)) {
                assembly ("memory-safe") {
                    mstore(0x14, addr)
                    mstore(0x00, 0x1abe960c000000000000000000000000) // selector for `NoReverseResolver(address)` with `addr`'s padding
                    revert(0x10, 0x24)
                }
            }
            name = resolver.name(node);
            if (bytes(name).length == 0) {
                assembly ("memory-safe") {
                    mstore(0x40, resolver)
                    mstore(0x2c, shl(0x60, addr)) // clears `resolver`'s padding
                    mstore(0x0c, 0xa50202b2000000000000000000000000) // selector for `NoReverseRecord(address,address)` with `addr`'s padding
                    revert(0x1c, 0x44)
                }
            }
        }
        require(bytes(name).length != 0);

        // check and namehash
        node = _nameHash(name);

        // check that the reverse-resolved node forward-resolves to the original
        // address
        if (node == bytes32(0)) {
            assembly ("memory-safe") {
                mstore(0x00, 0xca1e7dfd) // selector for `ENSRoot()`
                revert(0x1c, 0x04)
            }
        }
        {
            address forward = toAddr(node);
            if (forward != addr) {
                assembly ("memory-safe") {
                    mstore(0x54, and(0xffffffffffffffffffffffffffffffffffffffff, forward))
                    mstore(0x34, node)
                    mstore(0x14, addr)
                    mstore(0x00, 0x03bdaaf9000000000000000000000000) // selector for `ReverseForwardMismatch(address,bytes32,address)` with `addr`'s padding
                    revert(0x10, 0x64)
                }
            }
        }
    }
}

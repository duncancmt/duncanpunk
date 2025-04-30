// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {DuncanPunkERC721} from "src/DuncanPunkERC721.sol";

import {IPFS} from "src/lib/IPFS.sol";

import {Script} from "@forge-std/Script.sol";
import {VmSafe} from "@forge-std/Vm.sol";

import {console} from "@forge-std/console.sol";

contract Deploy is Script {
    function run() public {
        string memory image = vm.readFile(string.concat(vm.projectRoot(), "/image.svg"));
        string memory imageUri = IPFS.CIDv0(IPFS.dagPbUnixFsHash(image));
        console.log("image URI", imageUri);
        assert(keccak256(bytes(imageUri)) == keccak256("ipfs://QmZh6ajVwQhWKfuihGisUatLCLGdfbHbM8NsdXwHSVJ2UN"));

        bytes20 gitCommit;
        {
            string[] memory gitCommand = new string[](3);
            gitCommand[0] = "git";
            gitCommand[1] = "rev-parse";
            gitCommand[2] = "HEAD";
            VmSafe.FfiResult memory result = vm.tryFfi(gitCommand);
            assert(result.exitCode == 0);
            assert(result.stderr.length == 0);
            assert(result.stdout.length == 20);
            gitCommit = bytes20(result.stdout);
        }

        string memory imageEscaped;
        {
            string[] memory jqCommand = new string[](4);
            jqCommand[0] = "jq";
            jqCommand[1] = "-Rs";
            jqCommand[2] = ".";
            jqCommand[3] = "image.svg";
            VmSafe.FfiResult memory result = vm.tryFfi(jqCommand);
            assert(result.exitCode == 0);
            assert(result.stderr.length == 0);
            imageEscaped = string(result.stdout);
        }

        vm.startBroadcast();
        DuncanPunkERC721 token = new DuncanPunkERC721(gitCommit, image, imageEscaped);
        vm.stopBroadcast();

        assert(keccak256(bytes(token.tokenURI(1))) == keccak256("ipfs://QmQjU12eQzRkfeYCFQ7QAsrUY7xqMviZ7SY56C7dwEwQwS"));
    }
}

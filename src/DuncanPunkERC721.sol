// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC165} from "@forge-std/interfaces/IERC165.sol";
import {IERC721ViewMetadata} from "./interfaces/IERC721View.sol";

import {FastLogic} from "./lib/FastLogic.sol";
import {IPFS} from "./lib/IPFS.sol";
import {ENS} from "./lib/ENS.sol";

contract DuncanPunkERC721 is IERC721ViewMetadata {
    using FastLogic for bool;
    using IPFS for string;
    using IPFS for bytes32;
    using ENS for address;
    using ENS for string;
    using ENS for bytes32;

    bytes32 internal immutable _ensNode;
    bytes32 internal immutable _tokenUriHash;

    address internal lastOwner;

    event GitCommit(bytes20 indexed gitCommit);

    constructor(bytes20 gitCommit, string memory image, string memory imageEscaped) {
        emit GitCommit(gitCommit);

        assembly ("memory-safe") {
            log0(add(0x20, image), mload(image))
        }

        string memory imageUri = image.dagPbUnixFsHash().CIDv0();
        string memory tokenUriContents = string.concat(
            "{\"image\":\"",
            imageUri,
            "\",\"image_data\":",
            imageEscaped,
            ",\"description\":\"Profile picture for duncancmt.eth\",\"name\":\"",
            name,
            "\",\"background_color\":\"628495\"}\n"
        );
        _tokenUriHash = tokenUriContents.dagPbUnixFsHash();

        _ensNode = string("duncancmt.eth").toNode();
        poke();
    }

    function supportsInterface(bytes4 interfaceId) external pure override returns (bool) {
        uint256 interfaceIdInt = uint32(interfaceId);
        return (interfaceIdInt == uint32(type(IERC165).interfaceId))
            .or(interfaceIdInt == 0x80ac58cd /* regular IERC721 */)
            .or(interfaceIdInt == uint32(type(IERC721ViewMetadata).interfaceId));
    }

    function balanceOf(address acct) external view override returns (uint256 r) {
        bool isOwner = acct == _ensNode.toAddr();
        assembly ("memory-safe") {
            r := isOwner
        }
    }

    function getApproved(uint256 tokenId) external pure override returns (address) {
        require(tokenId == 1);
        return address(0);
    }

    function isApprovedForAll(address, address) external pure override returns (bool) {
        return false;
    }

    function ownerOf(uint256 tokenId) external view override returns (address) {
        require(tokenId == 1);
        return _ensNode.toAddr();
    }

    string public constant override name = "duncanpunk";
    string public constant override symbol = "DCMTPFP";

    function tokenURI(uint256 tokenId) external view override returns (string memory) {
        require(tokenId == 1);
        return _tokenUriHash.CIDv0();
    }

    function poke() public {
        address currentOwner = _ensNode.toAddr();
        address prevOwner = lastOwner;
        if (currentOwner != prevOwner) {
            lastOwner = prevOwner;
            emit Transfer(prevOwner, currentOwner, 1);
        }
    }
}

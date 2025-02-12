// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";

contract MockERC721 is ERC721 {
    uint256 private _currentTokenId;

    constructor(string memory name, string memory symbol) ERC721(name, symbol) {}

    function mint(address to) external {
        uint256 newTokenId = ++_currentTokenId;
        _mint(to, newTokenId);
    }

    function transfer(address to, uint256 tokenId) external {
        ERC721.transferFrom(msg.sender, to, tokenId);
    }

    function balanceOf(address owner) public view virtual override returns (uint256) {
        return ERC721.balanceOf(owner);
    }
}

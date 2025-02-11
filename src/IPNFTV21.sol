// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { ERC1155Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC1155/ERC1155Upgradeable.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import { ERC1155URIStorageUpgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC1155/extensions/ERC1155URIStorageUpgradeable.sol";
import { ERC1155BurnableUpgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC1155/extensions/ERC1155BurnableUpgradeable.sol";
import { ERC1155SupplyUpgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC1155/extensions/ERC1155SupplyUpgradeable.sol";
import { CountersUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/CountersUpgradeable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { IAuthorizeMints } from "./IAuthorizeMints.sol";
import { IReservable } from "./IReservable.sol";

/*
.____________________  ______________________     ________      ____ 
|   \______   \      \ \_   _____/\__    ___/__  _\_____  \    /_   |
|   ||     ___/   |   \ |    __)    |    |  \  \/ //  ____/     |   |
|   ||    |  /    |    \|     \     |    |   \   //       \     |   |
|___||____|  \____|__  /\___  /     |____|    \_/ \_______ \ /\ |___|
                     \/     \/                            \/ \/      */

/// @title IPNFTV2.1 Demo for Testing Upgrades
/// @author molecule.to
/// @notice Demo contract to test upgrades. Don't use like this
/// @dev Don't use this.

contract IPNFTV21 is
    IReservable,
    ERC1155Upgradeable,
    ERC1155BurnableUpgradeable,
    ERC1155SupplyUpgradeable,
    ERC1155URIStorageUpgradeable,
    UUPSUpgradeable,
    OwnableUpgradeable,
    PausableUpgradeable
{
    using CountersUpgradeable for CountersUpgradeable.Counter;

    CountersUpgradeable.Counter private _reservationCounter;
    mapping(uint256 => address) public reservations;

    /// @notice Current version of the contract
    uint16 internal _version;

    /// @notice e.g. a mintpass contract
    IAuthorizeMints mintAuthorizer;

    mapping(uint256 => mapping(address => uint256)) internal readAllowances;

    /// @notice musnt't take the Pauseable property gap
    string public aNewProperty;

    /**
     *
     * EVENTS
     *
     */

    event Reserved(address indexed reserver, uint256 indexed reservationId);
    event IPNFTMinted(address indexed minter, uint256 indexed tokenId, string tokenURI);

    /// @dev https://docs.opensea.io/docs/metadata-standards#freezing-metadata
    event PermanentURI(string _value, uint256 indexed _id);

    /**
     *
     * ERRORS
     *
     */
    error NotOwningReservation(uint256 id);
    error ToZeroAddress();
    error NeedsMintpass();
    error InsufficientBalance();

    /*
     *
     * DEPLOY
     *
     */

    /// @notice Contract constructor logic
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Contract initialization logic
    function initialize() public initializer {
        __UUPSUpgradeable_init();
        __Ownable_init();
        __Pausable_init();
        __ERC1155_init("");
        __ERC1155Burnable_init();
        __ERC1155URIStorage_init();
        __ERC1155Supply_init();

        _reservationCounter.increment(); //start at 1.
    }

    function reinit() public onlyOwner reinitializer(2) {
        aNewProperty = "some property";
    }

    /**
     *
     * PUBLIC
     *
     */

    /// @notice sets the address of the external authorizer contract
    function setAuthorizer(address authorizer_) public onlyOwner {
        if (authorizer_ == address(0)) {
            revert ToZeroAddress();
        }
        mintAuthorizer = IAuthorizeMints(authorizer_);
    }

    /// @notice reserves a new token id. Checks that the caller is authorized, according to the current implementation of IAuthorizeMints.
    function reserve() public returns (uint256) {
        if (!mintAuthorizer.authorizeReservation(_msgSender())) {
            revert NeedsMintpass();
        }

        uint256 reservationId = _reservationCounter.current();
        _reservationCounter.increment();
        reservations[reservationId] = _msgSender();
        emit Reserved(_msgSender(), reservationId);
        return reservationId;
    }

    /**
     * @notice mints an IPNFT with `tokenURI` as source of metadata. Invalidates the reservation. Redeems `mintpassId` on the authorizer contract
     * @param to address the recipient of the NFT
     * @param reservationId the reserved token id that has been reserved with `reserve()`
     * @param mintPassId an id that's handed over to the `IAuthorizeMints` interface
     * @param tokenURI a location that resolves to a valid IP-NFT metadata structure
     */
    function mintReservation(address to, uint256 reservationId, uint256 mintPassId, string memory tokenURI) public override returns (uint256) {
        if (reservations[reservationId] != _msgSender()) {
            revert NotOwningReservation(reservationId);
        }

        mintAuthorizer.authorizeMint(_msgSender(), to, abi.encode(mintPassId));

        //todo: emit this, once we decided if we're sure that this one is going to be final.
        //emit PermanentURI(tokenURI, reservationId);
        delete reservations[reservationId];
        mintAuthorizer.redeem(abi.encode(mintPassId));

        _mint(to, reservationId, 1, "");
        _setURI(reservationId, tokenURI);

        emit IPNFTMinted(to, reservationId, tokenURI);
        return reservationId;
    }

    function increaseShares(uint256 tokenId, uint256 shares, address to) public {
        require(shares > 0, "IP-NFT: shares amount must be greater than 0");
        require(totalSupply(tokenId) == 1, "IP-NFT: shares already minted");
        require(balanceOf(_msgSender(), tokenId) == 1, "IP-NFT: not owner");

        _mint(to, tokenId, shares, "");
    }

    function distribute(uint256 fromToken, address[] memory toAddresses, uint256 value) public {
        for (uint256 i = 0; i < toAddresses.length; i++) {
            safeTransferFrom(msg.sender, toAddresses[i], fromToken, value, "");
        }
    }

    /**
     * @notice grants time limited "read" access to gated resources
     * @param reader the address that should be able to access gated content
     * @param tokenId token id
     * @param until the timestamp when read access expires (unsafe but good enough for this use case)
     */
    function grantReadAccess(address reader, uint256 tokenId, uint256 until) public {
        if (balanceOf(_msgSender(), tokenId) == 0) {
            revert InsufficientBalance();
        }

        require(until > block.timestamp, "until in the past");

        readAllowances[tokenId][reader] = until;
    }

    /**
     * @notice check whether `reader` shall be able to access gated content behind `tokenId`
     * @param reader the address in question
     * @param tokenId token id
     * @return bool current read allowance
     */
    function canRead(address reader, uint256 tokenId) public view returns (bool) {
        if (balanceOf(reader, tokenId) > 0) {
            return true;
        }
        return readAllowances[tokenId][reader] > block.timestamp;
    }

    // Withdraw ETH from contract
    function withdrawAll() public payable onlyOwner {
        require(payable(_msgSender()).send(address(this).balance), "transfer failed");
    }

    // The following functions are overrides required by Solidity.

    function _beforeTokenTransfer(address operator, address from, address to, uint256[] memory ids, uint256[] memory amounts, bytes memory data)
        internal
        override (ERC1155Upgradeable, ERC1155SupplyUpgradeable)
    {
        super._beforeTokenTransfer(operator, from, to, ids, amounts, data);
    }

    function uri(uint256 tokenId) public view virtual override (ERC1155Upgradeable, ERC1155URIStorageUpgradeable) returns (string memory) {
        return ERC1155URIStorageUpgradeable.uri(tokenId);
    }

    /// @notice upgrade authorization logic
    function _authorizeUpgrade(address /*newImplementation*/ )
        internal
        override
        onlyOwner // solhint-disable-next-line no-empty-blocks
    {
        //empty block
    }
}

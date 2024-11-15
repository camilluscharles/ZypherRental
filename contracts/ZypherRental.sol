// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/// @title ZypherRental - Manages Rentals and KYC with NFTs
contract ZypherRental is ERC721, Ownable {
    address public admin;
    uint public nextRentalTokenId = 1;  // Tracks next rental item token ID
    uint public nextKYCTokenId = 10000; // Start KYC NFTs from a distinct range

    constructor(address initialOwner) ERC721("ZypherItem", "ZYI") Ownable(initialOwner) {
        admin = initialOwner;
    }

    struct Rental {
        uint itemId;
        uint price;
        address payable seller;
        address payable buyer;
        bool isPaid;
        bool isReceived;
        bool isConfirmed;
        bool isDisputed;
        uint creationTime;
        uint tokenId; // Unique ID for rental NFT
    }

    mapping(uint => Rental) public rentals;
    mapping(address => bool) public kycStatus;
    mapping(address => uint) public kycTokenIds; // Stores the KYC NFT ID for each user

    event DisputeRaised(uint rentalId);
    event RentalResolved(uint rentalId, bool decision);
    event RentalCreated(uint itemId, uint price, uint tokenId);
    event RentalPaid(uint itemId, address buyer);
    event ReceiptConfirmed(uint itemId);
    event RefundIssued(uint itemId, address buyer);

    modifier onlyAdmin() {
        require(msg.sender == admin, "Only admin can perform this action");
        _;
    }

    modifier onlyKYCVerified() {
        require(kycStatus[msg.sender] == true, "KYC verification required");
        _;
    }

    // KYC Functions
    function submitKYC() public {
        require(!kycStatus[msg.sender], "User  already submitted KYC");
        kycStatus[msg.sender] = true; // Indicate that the user has submitted KYC
    }

    function approveKYC(address _user) public onlyAdmin {
        require(!kycStatus[_user], "User  already KYC approved");

        // Mint KYC NFT for the user
        uint kycTokenId = nextKYCTokenId;
        nextKYCTokenId++;
        _safeMint(_user, kycTokenId);

        kycStatus[_user] = true;
        kycTokenIds[_user] = kycTokenId; // Store the KYC token ID for the user
    }

    // Rental Management Functions
    function createRental(uint _itemId, uint _price) public onlyKYCVerified {
        require(rentals[_itemId].seller == address(0), "Rental already exists for this itemId");

        uint tokenId = nextRentalTokenId;
        nextRentalTokenId++;
        
        // Mint NFT to the seller for the rental item
        _safeMint(msg.sender, tokenId);

        rentals[_itemId] = Rental({
            itemId: _itemId,
            price: _price,
            seller: payable(msg.sender),
            buyer: payable(address(0)),
            isPaid: false,
            isReceived: false,
            isConfirmed: false,
            isDisputed: false,
            creationTime: block.timestamp,
            tokenId: tokenId  // Associate tokenId with the rental
        });

        emit RentalCreated(_itemId, _price, tokenId);
    }

    function rentItem(uint _itemId) public payable onlyKYCVerified {
        Rental storage rental = rentals[_itemId];
        require(rental.seller != address(0), "Item does not exist");
        require(!rental.isPaid, "Item already rented");
        require(msg.value == rental.price, "Incorrect rental price");

        rental.buyer = payable(msg.sender);
        rental.isPaid = true;
        rental.creationTime = block.timestamp;

        emit RentalPaid(_itemId, msg.sender);
    }

    function confirmReceipt(uint _itemId) public {
        Rental storage rental = rentals[_itemId];
        require(msg.sender == rental.buyer, "Only buyer can confirm receipt");
        require(rental.isPaid, "Rental not paid for");
        require(!rental.isConfirmed, "Already confirmed");

        rental.isReceived = true;
        rental.isConfirmed = true;

        // Transfer the rental NFT to the buyer
        _safeTransfer(rental.seller, rental.buyer, rental.tokenId, "");
        
        rental.seller.transfer(rental.price); // Release funds to seller

        emit ReceiptConfirmed(_itemId);
    }

    function refundBuyer(uint _itemId) public {
        Rental storage rental = rentals[_itemId];
        require(msg.sender == rental.buyer, "Only buyer can request a refund");
 require(rental.isPaid, "Rental not paid for");
        require(!rental.isConfirmed, "Cannot refund after confirmation");

        rental.isPaid = false; // Mark rental as unpaid
        rental.buyer.transfer(rental.price); // Refund the buyer

        emit RefundIssued(_itemId, msg.sender);
    }

    function raiseDispute(uint _itemId) public {
        Rental storage rental = rentals[_itemId];
        require(msg.sender == rental.buyer, "Only buyer can raise a dispute");
        require(rental.isPaid, "Rental not paid for");
        require(!rental.isDisputed, "Dispute already raised");

        rental.isDisputed = true;

        emit DisputeRaised(_itemId);
    }

    function resolveDispute(uint _itemId, bool decision) public onlyAdmin {
        Rental storage rental = rentals[_itemId];
        require(rental.isDisputed, "No dispute to resolve");

        rental.isDisputed = false; // Mark dispute as resolved
        if (decision) {
            rental.isConfirmed = true; // Confirm the rental
            rental.seller.transfer(rental.price); // Release funds to seller
        } else {
            rental.buyer.transfer(rental.price); // Refund the buyer
        }

        emit RentalResolved(_itemId, decision);
    }
}
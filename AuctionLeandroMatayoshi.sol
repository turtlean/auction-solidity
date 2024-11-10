// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

contract AuctionLeandroMatayoshi {
    address public owner;
    address public seller;

    // Time-related variables
    uint public startTimestamp;
    uint public bidDurationInSeconds;
    uint public extensionTimeAfterBidInSeconds;
    uint public latestBidTimestamp;

    // Amount-related variable
    uint256 internal initialValue;
    uint256 public minimumPercentageIncreaseInBid;

    // State variables
    address[] internal addresses;
    mapping(address => uint[]) internal remainingBidsByAddress;
    mapping(address => uint) internal highestBidByAddress;
    uint internal highestBid;
    address internal highestBidder;
    bool public auctionEnded;

    // Events
    event BidPlaced(address bidder, uint amount);
    event HighestBidIncreased(address bidder, uint amount);
    event AuctionEnded(address winner, uint amount);

    // Modifiers
    modifier onlyOwner() {
        require(msg.sender == owner, "Not the contract owner");
        _;
    }

    modifier auctionActive() {
        require(!auctionEnded, "Auction already ended");
        _;
    }

    constructor(
        address _seller,
        uint256 _initialValue,
        uint256 _minPercentageIncrease,
        uint _bidDurationInSeconds,
        uint _extensionInSeconds
    ) {
        seller = _seller;

        // Time-related variables
        startTimestamp = block.timestamp;
        bidDurationInSeconds = _bidDurationInSeconds;
        extensionTimeAfterBidInSeconds = _extensionInSeconds;

        // Amount-related variables
        initialValue = _initialValue;
        assert(_minPercentageIncrease > 0);
        minimumPercentageIncreaseInBid = _minPercentageIncrease;

        // State variables
        highestBid = 0;
        highestBidder = address(0); // Initialize to the default address
        auctionEnded = false;
    }

    function placeBid() external payable auctionActive {
        emit BidPlaced(msg.sender, msg.value);

        require(
            block.timestamp < startTimestamp + bidDurationInSeconds ||
                block.timestamp <
                latestBidTimestamp + extensionTimeAfterBidInSeconds,
            "Extension time has finished, it's not possible to bid anymore"
        );

        if (highestBid == 0) {
            require(
                msg.value > initialValue,
                "Bid should be higher than the initial value"
            );
        } else {
            require(
                msg.value <
                    highestBid +
                        (highestBid * minimumPercentageIncreaseInBid) /
                        100,
                "The bid should be at least the minimum percentage increase over the highest bid"
            );
        }

        if (highestBidByAddress[msg.sender] == 0) {
            assert(remainingBidsByAddress[msg.sender].length == 0);
        } else {
            remainingBidsByAddress[msg.sender].push(
                highestBidByAddress[msg.sender]
            );
        }

        highestBidByAddress[msg.sender] = msg.value;
        highestBidder = msg.sender;
        highestBid = msg.value;
        latestBidTimestamp = block.timestamp;
        emit HighestBidIncreased(msg.sender, msg.value);
    }

    function getBids() external view returns (address[] memory, uint[] memory) {
        uint totalBidsCount = 0;

        // Count total bids
        for (uint i = 0; i < addresses.length; i++) {
            totalBidsCount += remainingBidsByAddress[addresses[i]].length;
            require(highestBidByAddress[addresses[i]] > 0, "Highest bid is 0");
            totalBidsCount++;
        }

        address[] memory allAddresses = new address[](totalBidsCount);
        uint[] memory allBids = new uint[](totalBidsCount);

        // Populate addresses and bids arrays
        uint index = 0;
        for (uint i = 0; i < addresses.length; i++) {
            // Include the highest bid at the beginning
            allAddresses[index] = addresses[i];
            allBids[index] = highestBidByAddress[addresses[i]];
            index++;
            for (
                uint j = 0;
                j < remainingBidsByAddress[addresses[i]].length;
                j++
            ) {
                allAddresses[index] = addresses[i];
                allBids[index] = remainingBidsByAddress[addresses[i]][j];
                index++;
            }
        }

        return (allAddresses, allBids);
    }

    function getHighestBid() external view returns (address, uint) {
        return (highestBidder, highestBid);
    }

    function withdrawPreviousBids() external {
        uint[] memory previousBids = remainingBidsByAddress[msg.sender];
        uint total = 0;
        for (uint i = 0; i < previousBids.length; i++) {
            total += previousBids[i];
        }
        require(total > 0, "No previous bids to withdraw");
        require(
            address(this).balance >= total,
            "Contract balance is insufficient"
        );

        payable(msg.sender).transfer(total);
        delete remainingBidsByAddress[msg.sender];
    }

    function endAuction() public onlyOwner auctionActive {
        auctionEnded = true;

        for (uint i = 0; i < addresses.length; i++) {
            if (addresses[i] != highestBidder) {
                uint refundAmount = (highestBidByAddress[addresses[i]] * 98) /
                    100;
                require(
                    address(this).balance >= refundAmount,
                    "Contract balance is insufficient"
                );
                payable(addresses[i]).transfer(refundAmount);
                highestBidByAddress[addresses[i]] = 0;
            }
        }

        require(
            address(this).balance >= (highestBid * 98) / 100,
            "Contract balance is insufficient"
        );
        payable(seller).transfer((highestBid * 98) / 100);

        // Contract remains open so participants can withdraw their previous bids

        emit AuctionEnded(highestBidder, highestBid);
    }
}

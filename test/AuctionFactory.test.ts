// test/AuctionFactory.test.ts
import { expect } from "chai";
import { ethers } from "hardhat";
import { BigNumber, Contract, Signer } from "ethers";
import { delay } from "@nomiclabs/hardhat-etherscan/dist/src/etherscan/EtherscanService";

describe("AuctionFactory", function () {
  let auctionFactory: Contract;
  let nft: Contract;
  let owner: Signer;
  let user1: Signer;
  let user2: Signer;

  const State = {
    Created: 0,
    Started: 1,
    Canceled: 2,
    Resolved: 3,
  };

  beforeEach(async function () {
    [owner, user1, user2] = await ethers.getSigners();
    const AuctionFactoryToken = await ethers.getContractFactory(
      "AuctionFactory"
    );
    const NFTToken = await ethers.getContractFactory("NFTToken");
    nft = await NFTToken.deploy();
    await nft.safeMint(await owner.getAddress());
    await nft.safeMint(await user1.getAddress());
    auctionFactory = await AuctionFactoryToken.deploy(nft.address);
    await auctionFactory.create(
      0,
      3, // 3s
      ethers.utils.parseEther("1"),
      5 // 5%
    );
    await nft.setApprovalForAll(auctionFactory.address, true);
  });

  it("Should set the right and check balance of seller", async function () {
    // Expect receives a value, and wraps it in an Assertion object. These
    // objects have a lot of utility methods to assert values.

    // This test expects the seller variable stored in the contract to be equal
    // to our Signer's owner.
    const auctions = await auctionFactory.fetch(await owner.getAddress());
    expect(auctions[0].seller).to.equal(await owner.getAddress());
    expect(
      await auctionFactory.balanceOf(
        auctions[0].auctionId,
        await owner.getAddress()
      )
    ).to.equal(BigNumber.from(0));
  });

  it("Should bid test.", async () => {
    const auctions = await auctionFactory.fetch(await owner.getAddress());
    // Checking first bid
    expect(auctions[0].state).to.equal(State.Created);
    await expect(
      auctionFactory
        .connect(user1)
        .bid(auctions[0].auctionId, { value: ethers.utils.parseEther("0.5") })
    ).to.be.revertedWith("Insufficient fund");
    expect(
      await auctionFactory.balanceOf(
        auctions[0].auctionId,
        await user1.getAddress()
      )
    ).to.equal(BigNumber.from(0));
    await auctionFactory
      .connect(user1)
      .bid(auctions[0].auctionId, { value: ethers.utils.parseEther("1") });
    expect(
      (await auctionFactory.auctions(auctions[0].auctionId)).state
    ).to.equal(State.Started);
    expect(
      await auctionFactory.balanceOf(
        auctions[0].auctionId,
        await user1.getAddress()
      )
    ).to.equal(ethers.utils.parseEther("1"));

    // Checking second bid and highest bidder
    await expect(
      auctionFactory
        .connect(user2)
        .bid(auctions[0].auctionId, { value: ethers.utils.parseEther("1.04") })
    ).to.be.revertedWith("Insufficient fund");
    await auctionFactory
      .connect(user2)
      .bid(auctions[0].auctionId, { value: ethers.utils.parseEther("1.05") });
    expect(
      (await auctionFactory.auctions(auctions[0].auctionId)).highestBidder
    ).to.equal(await user2.getAddress());
  });

  it("Should withdraw test.", async () => {
    const auctions = await auctionFactory.fetch(await owner.getAddress());
    await auctionFactory
      .connect(user1)
      .bid(auctions[0].auctionId, { value: ethers.utils.parseEther("1") });
    await auctionFactory
      .connect(user2)
      .bid(auctions[0].auctionId, { value: ethers.utils.parseEther("1.05") });
    await expect(
      auctionFactory.connect(user2).withdraw(auctions[0].auctionId)
    ).to.be.revertedWith("Your funds are locked!");
    await auctionFactory.connect(user1).withdraw(auctions[0].auctionId);
    expect(
      await auctionFactory.balanceOf(
        auctions[0].auctionId,
        await user1.getAddress()
      )
    ).to.equal(BigNumber.from(0));
  });

  it("Should resolve test.", async () => {
    const auctions = await auctionFactory.fetch(await owner.getAddress());
    await expect(
      auctionFactory.resolve(auctions[0].auctionId)
    ).to.be.revertedWith("Auction was not started.");
    await auctionFactory
      .connect(user1)
      .bid(auctions[0].auctionId, { value: ethers.utils.parseEther("1") });
    await auctionFactory
      .connect(user2)
      .bid(auctions[0].auctionId, { value: ethers.utils.parseEther("1.05") });
    await delay(4000);
    expect(await nft.balanceOf(await user2.getAddress())).to.equal(
      BigNumber.from(0)
    );
    await auctionFactory.connect(user2).resolve(auctions[0].auctionId);
    expect(
      (await auctionFactory.auctions(auctions[0].auctionId)).state
    ).to.equal(State.Resolved);
    expect(await nft.balanceOf(await user2.getAddress())).to.equal(
      BigNumber.from(1)
    );
  });
  it("Should cancel test.", async () => {
    const auctions = await auctionFactory.fetch(await owner.getAddress());
    await expect(
      auctionFactory.connect(user1).cancel(auctions[0].auctionId)
    ).to.be.revertedWith("You are not a seller.");
    await auctionFactory
      .connect(user1)
      .bid(auctions[0].auctionId, { value: ethers.utils.parseEther("1") });
    await expect(
      auctionFactory.cancel(auctions[0].auctionId)
    ).to.be.revertedWith("You can't cancel this auction.");

    await auctionFactory.connect(user1).create(
      1,
      3, // 3s
      ethers.utils.parseEther("1"),
      5 // 5%
    );
    const newAuctions = await auctionFactory.fetch(await user1.getAddress());
    await auctionFactory.connect(user1).cancel(newAuctions[0].auctionId);
    expect(
      (await auctionFactory.auctions(newAuctions[0].auctionId)).state
    ).to.equal(State.Canceled);
  });
  it("Should create auction test.", async () => {
    await expect(
      auctionFactory.connect(user2).create(
        1,
        3, // 3s
        ethers.utils.parseEther("1"),
        5 // 5%
      )
    ).to.be.revertedWith("You have no this token.");
  });
});

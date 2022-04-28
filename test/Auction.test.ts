// test/Auction.test.ts
import { expect } from "chai";
import { ethers } from "hardhat";
import { BigNumber, Contract, Signer } from "ethers";
import { delay } from "@nomiclabs/hardhat-etherscan/dist/src/etherscan/EtherscanService";

describe("Auction", function () {
  let hardhatToken: Contract;
  let nft: Contract;
  let owner: Signer;
  let user1: Signer;
  let user2: Signer;
  let ownerAddress: string;

  beforeEach(async function () {
    [owner, user1, user2] = await ethers.getSigners();
    ownerAddress = await owner.getAddress();
    const Auction = await ethers.getContractFactory("Auction");
    const NFTToken = await ethers.getContractFactory("NFTToken");
    nft = await NFTToken.deploy();
    await nft.safeMint(ownerAddress);
    hardhatToken = await Auction.deploy(
      nft.address,
      0,
      3,
      ethers.utils.parseEther("1"),
      5
    );
    await nft.setApprovalForAll(hardhatToken.address, true);
  });

  it("Should set the right and check balance of seller", async function () {
    // Expect receives a value, and wraps it in an Assertion object. These
    // objects have a lot of utility methods to assert values.

    // This test expects the seller variable stored in the contract to be equal
    // to our Signer's owner.
    expect(await hardhatToken.seller()).to.equal(ownerAddress);
    expect(await hardhatToken.balanceOf(ownerAddress)).to.equal(
      BigNumber.from(0)
    );
  });

  it("Should bid test.", async () => {
    // Checking first bid
    expect(await hardhatToken.started()).to.equal(false);
    await expect(
      hardhatToken.connect(user1).bid({ value: ethers.utils.parseEther("0.5") })
    ).to.be.revertedWith("Insufficient fund");
    expect(await hardhatToken.balanceOf(await user1.getAddress())).to.equal(
      BigNumber.from(0)
    );
    expect(await hardhatToken.started()).to.equal(false);
    await hardhatToken
      .connect(user1)
      .bid({ value: ethers.utils.parseEther("1") });
    expect(await hardhatToken.balanceOf(await user1.getAddress())).to.equal(
      ethers.utils.parseEther("1")
    );
    expect(await hardhatToken.started()).to.equal(true);

    // Checking second bid and highest bidder
    await expect(
      hardhatToken
        .connect(user2)
        .bid({ value: ethers.utils.parseEther("1.04") })
    ).to.be.revertedWith("Insufficient fund");
    await hardhatToken
      .connect(user2)
      .bid({ value: ethers.utils.parseEther("1.05") });
    expect(await hardhatToken.highestBidder()).to.equal(
      await user2.getAddress()
    );
  });

  it("Should withdraw test.", async () => {
    await hardhatToken
      .connect(user1)
      .bid({ value: ethers.utils.parseEther("1") });
    await hardhatToken
      .connect(user2)
      .bid({ value: ethers.utils.parseEther("1.05") });
    await expect(hardhatToken.connect(user2).withdraw()).to.be.revertedWith(
      "Your funds are locked!"
    );
    await hardhatToken.connect(user1).withdraw();
    expect(await hardhatToken.balanceOf(await user1.getAddress())).to.equal(
      BigNumber.from(0)
    );
  });

  it("Should resolve test.", async () => {
    await expect(hardhatToken.resolve()).to.be.revertedWith(
      "Auction was not started."
    );
    await hardhatToken
      .connect(user1)
      .bid({ value: ethers.utils.parseEther("1") });
    await hardhatToken
      .connect(user2)
      .bid({ value: ethers.utils.parseEther("1.05") });
    await delay(4000);
    expect(await nft.balanceOf(await user2.getAddress())).to.equal(
      BigNumber.from(0)
    );
    await hardhatToken.connect(user1).resolve();
    expect(await nft.balanceOf(await user2.getAddress())).to.equal(
      BigNumber.from(1)
    );
  });
});

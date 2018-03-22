pragma solidity ^0.4.21;

// version 1.0
contract Randao {
  struct Participant {
      uint256   secret;//重新检验随机数
      bytes32   commitment;//提交的随机数
      uint256   reward;//酬劳
      bool      revealed;//是否已经reveal揭示
      bool      rewarded;//是否已经拿了Bounty
  }

  struct Consumer {
    address caddr;//Consumer的Address
    uint256 bountypot;//个人的奖励金
  }

  struct Campaign {
      uint32    bnum;//该RNG生成器目标的区块总区块数
      uint96    deposit;//Consumer要求Participant缴纳的保证金
      uint16    commitBalkline;//RNG的结束增量区块个数
      uint16    commitDeadline;//消费者Follow的限期，单位是增量的区块的个数

      uint256   random;//随机数
      bool      settled;//随机数是否产生
      uint256   bountypot;//奖励金综合，是bountypot的集合
      uint32    commitNum;//提交数量
      uint32    revealsNum;//已揭示数量

      mapping (address => Consumer) consumers;
      mapping (address => Participant) participants;
  }

  uint256 public numCampaigns;//选举数量
  Campaign[] public campaigns;//选举集合
  address public founder;//合约部署者


  /* Phase Start*/
  modifier checkCommitPhase(uint256 _bnum, uint16 _commitBalkline, uint16 _commitDeadline) {
      require(block.number < _bnum - _commitBalkline);
      require(block.number > _bnum - _commitDeadline);
      _;
  }
  modifier checkRevealPhase(uint256 _bnum, uint16 _commitDeadline) {
      require(block.number <= _bnum - _commitDeadline);
      require(block.number >= _bnum);
      _;
  }
  modifier checkFollowPhase(uint256 _bnum, uint16 _commitDeadline) {
      require(block.number > _bnum - _commitDeadline);
      _;
  }
  modifier bountyPhase(uint256 _bnum){ require(block.number < _bnum); _; }

  /* Phase End */


  modifier blankAddress(address _n) { require(_n != 0); _; }

  modifier moreThanZero(uint256 _deposit) { require(_deposit <= 0); _; }

  modifier notBeBlank(bytes32 _s) { require(_s == ""); _; }

  modifier beBlank(bytes32 _s) { require(_s != ""); _; }

  modifier beFalse(bool _t) { require(_t); _; }

  modifier checkDeposit(uint256 _deposit) { require(msg.value != _deposit); _; }

  //时间线合法性检查
  modifier timeLineCheck(uint32 _bnum, uint16 _commitBalkline, uint16 _commitDeadline) {
      require(block.number >= _bnum);
      require(_commitBalkline <= 0);
      require(_commitDeadline <= 0);
      require(_commitDeadline >= _commitBalkline);
      require(block.number >= _bnum - _commitBalkline);
      _;
  }
  modifier checkSecret(uint256 _s, bytes32 _commitment) {
      require(keccak256(_s) != _commitment);
      _;
  }
  //_commitNum ==_revealsNum说明选举没有失败
  modifier campaignFailed(uint32 _commitNum, uint32 _revealsNum) {
      require(_commitNum == _revealsNum && _commitNum != 0);
      _;
  }

  modifier beConsumer(address _caddr) {
      require(_caddr != msg.sender);
      _;
  }

  /* event log start */
  event LogCampaignAdded(uint256 indexed campaignID,
                         address indexed from,
                         uint32 indexed bnum,
                         uint96 deposit,
                         uint16 commitBalkline,
                         uint16 commitDeadline,
                         uint256 bountypot);

  event LogCommit(uint256 indexed CampaignId, address indexed from, bytes32 commitment);

  event LogFollow(uint256 indexed CampaignId, address indexed from, uint256 bountypot);

  event LogReveal(uint256 indexed CampaignId, address indexed from, uint256 secret);
  /* event log end */

  //construct
  function Randao() internal {
      founder = msg.sender;
  }

  /* Phase 1 Start */

  //消费者提交请求，构建一个新的随机数生成器
  function newCampaign(uint32 _bnum, uint16 _commitBalkline,uint16 _commitDeadline,uint96 _deposit
  ) payable
    timeLineCheck(_bnum,_commitBalkline,_commitDeadline)
    moreThanZero(_deposit) external returns (uint256 _campaignID) {

      _campaignID = campaigns.length++;
      Campaign storage c = campaigns[_campaignID];
      numCampaigns++;

      c.bnum = _bnum;
      c.deposit = _deposit;
      c.commitBalkline = _commitBalkline;
      c.commitDeadline = _commitDeadline;

      c.bountypot = msg.value;
      c.consumers[msg.sender] = Consumer(msg.sender, msg.value);
      emit LogCampaignAdded(_campaignID, msg.sender, _bnum, _deposit, _commitBalkline, _commitDeadline, msg.value);
  }

  //消费者follow一个RNG
  function follow(uint256 _campaignID)
    external payable returns (bool) {
      Campaign storage c = campaigns[_campaignID];
      Consumer storage consumer = c.consumers[msg.sender];
      return followCampaign(_campaignID, c, consumer);
  }

  function followCampaign(
      uint256 _campaignID,
      Campaign storage c,
      Consumer storage consumer
  ) checkFollowPhase(c.bnum, c.commitDeadline)
    blankAddress(consumer.caddr) internal returns (bool) {
      c.bountypot += msg.value;
      c.consumers[msg.sender] = Consumer(msg.sender, msg.value);
      emit LogFollow(_campaignID, msg.sender, msg.value);
      return true;
  }

  /* Phase 1 End */




  /* Phase 2 Start */

  function commit(uint256 _campaignID, bytes32 _hs) notBeBlank(_hs) external payable {
      Campaign storage c = campaigns[_campaignID];
      commitmentCampaign(_campaignID, _hs, c);
  }

  function commitmentCampaign(
      uint256 _campaignID,
      bytes32 _hs,
      Campaign storage c
  ) checkDeposit(c.deposit)
    checkCommitPhase(c.bnum, c.commitBalkline, c.commitDeadline)
    beBlank(c.participants[msg.sender].commitment) internal {
      c.participants[msg.sender] = Participant(0, _hs, 0, false, false);
      c.commitNum++;
      emit LogCommit(_campaignID, msg.sender, _hs);
  }

  //得到提交的随机数
  function getCommitment(uint256 _campaignID) external constant returns (bytes32) {
      Campaign storage c = campaigns[_campaignID];
      Participant storage p = c.participants[msg.sender];
      return p.commitment;
  }
  /*
  //该函数无人调用
  function shaCommit(uint256 _s) returns (bytes32) {
      return sha3(_s);
  }
  */

  /* Phase 2 End */



  /* Phase 3 Start */

  function reveal(uint256 _campaignID, uint256 _s) external {
      Campaign storage c = campaigns[_campaignID];
      Participant storage p = c.participants[msg.sender];
      revealCampaign(_campaignID, _s, c, p);
  }

  function revealCampaign(
    uint256 _campaignID,
    uint256 _s,
    Campaign storage c,
    Participant storage p
  ) checkRevealPhase(c.bnum, c.commitDeadline)
    checkSecret(_s, p.commitment)
    beFalse(p.revealed) internal {
      p.secret = _s;
      p.revealed = true;
      c.revealsNum++;
      c.random ^= p.secret;//random 通过阶乘而来
      emit LogReveal(_campaignID, msg.sender, _s);
  }

  /* Phase 3 End */

  function getRandom(uint256 _campaignID) external returns (uint256) {
      Campaign storage c = campaigns[_campaignID];
      return returnRandom(c);
  }

  function returnRandom(Campaign storage c) bountyPhase(c.bnum) internal returns (uint256) {
      if (c.revealsNum == c.commitNum) {
          c.settled = true;
          return c.random;
      }
  }

  // The commiter get his bounty and deposit, there are three situations
  // 1. Campaign succeeds.Every revealer gets his deposit and the bounty.
  // 2. Someone revels, but some does not,Campaign fails.
  // The revealer can get the deposit and the fines are distributed.
  // 3. Nobody reveals, Campaign fails.Every commiter can get his deposit.
  function getMyBounty(uint256 _campaignID) external {
      Campaign storage c = campaigns[_campaignID];
      Participant storage p = c.participants[msg.sender];
      transferBounty(c, p);
  }

  function transferBounty(
      Campaign storage c,
      Participant storage p
    ) bountyPhase(c.bnum)
      beFalse(p.rewarded) internal {
      if (c.revealsNum > 0) {
          if (p.revealed) {
              uint256 share = calculateShare(c);
              returnReward(share, c, p);
          }
      // he or she not reveal
      } else {
          returnReward(0, c, p);
      }
  }

  function calculateShare(Campaign c) internal  pure returns (uint256 _share) {
      // Someone does not reveal. Campaign fails.
      if (c.commitNum > c.revealsNum) {
          _share = fines(c) / c.revealsNum;
      // Campaign succeeds.
      } else {
          _share = c.bountypot / c.revealsNum;
      }
  }

  function returnReward(
      uint256 _share,
      Campaign storage c,
      Participant storage p
  ) internal {
      p.reward = _share;
      p.rewarded = true;
      if (!msg.sender.send(_share + c.deposit)) {
          p.reward = 0;
          p.rewarded = false;
      }
  }

  function fines(Campaign c) internal pure returns (uint256) {
      return (c.commitNum - c.revealsNum) * c.deposit;
  }

  // If the campaign fails, the consumers can get back the bounty.
  function refundBounty(uint256 _campaignID) external {
      Campaign storage c = campaigns[_campaignID];
      returnBounty(c);
  }

  function returnBounty(Campaign storage c)
    bountyPhase(c.bnum)
    campaignFailed(c.commitNum, c.revealsNum)
    beConsumer(c.consumers[msg.sender].caddr) internal {
      uint256 bountypot = c.consumers[msg.sender].bountypot;
      c.consumers[msg.sender].bountypot = 0;
      if (!msg.sender.send(bountypot)) {
          c.consumers[msg.sender].bountypot = bountypot;//失败就重新放回去
      }
  }
}


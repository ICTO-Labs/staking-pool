/**
 * Module     : main.mo
 * Copyright  : 2022 Canister Team
 * License    : Apache 2.0 with LLVM Exception
 * Maintainer : Canister Team <dev@canister.app>
 * Stability  : Experimental
 */

import HashMap "mo:base/HashMap";
import Principal "mo:base/Principal";
import AccountBlob "mo:principal/blob/AccountIdentifier";
import AccountIdentifier "mo:principal/blob/AccountIdentifier";
import Time "mo:base/Time";
import Iter "mo:base/Iter";
import Array "mo:base/Array";
import Buffer "mo:base/Buffer";
import Cycles "mo:base/ExperimentalCycles";
import Error "mo:base/Error";

import Option "mo:base/Option";
import Order "mo:base/Order";
import Blob "mo:base/Blob";
import Bool "mo:base/Bool";
import Nat "mo:base/Nat";
import Float "mo:base/Float";
import Int "mo:base/Int";
import Nat8 "mo:base/Nat8";
import Nat32 "mo:base/Nat32";
import Nat64 "mo:base/Nat64";
import Result "mo:base/Result";
import Text "mo:base/Text";
import ExperimentalCycles "mo:base/ExperimentalCycles";
import Ext "mo:ext/Ext";
import Types "types";
import Functions "functions";
import Actor "actor";
import Data "data";
shared ({ caller = creator }) actor class CanicNFT(
    cid    : Principal, //This is Principal of this Canister.
) = {


  private stable var _stakingCanister = "2tvxo-eqaaa-aaaai-acjla-cai";
  private stable var _rewardCanister = "e2gn7-5aaaa-aaaal-abata-cai";
  //Pool INIT
  private stable var _stakingPool      : Types.StakingPool = {
      name = "Staking Pool";
      endTime = Time.now();
      rewardPerSecond = 0;
      rewardStandard = "";
      rewardSymbol = "";
      rewardToken = "";
      rewardTokenDecimals = 8;
      rewardTokenFee = 0;
      stakingStandard = "";
      stakingSymbol = "";
      stakingToken = "";
      startTime  = Time.now();
      totalRewards  = 0;
  };

  //Define actor canister
  let NFTCanister : Actor.NFT = actor(_stakingCanister);//Staking Canister: "mxftc-eyaaa-aaaap-qanga-cai"
  let TokenCanister : Actor.Token = actor(_rewardCanister);//"qi26q-6aaaa-aaaap-qapeq-cai");//Reward Canister


  private stable var _admins              : [Principal] = [creator];
  private stable var _nextSubAccount      : Nat = 0;
  private stable var _tranIdx             : Nat = 0;
  private stable var _harvestIdx          : Nat = 0;

  // Heartbeat - System cronjob
  private stable var s_heartbeatIntervalSeconds : Nat = 600;//Distribute every 1 minute
  private stable var s_heartbeatLastBeat : Int = 0;
  private stable var s_heartbeatOn : Bool = true;

  // Pool setting
  private stable var _totalWeight : Int = 0; //This is base on NRI, Tier...
  private stable var _totalRewarded : Nat64 = 0; //Total rewarded counter.


  private stable var _minimumHarvest: Nat = 1_000_000;//Minimum 1 Token

  // Unfinalized transactions.
  private var admins : Buffer.Buffer<Principal> = Buffer.Buffer(0);

  private stable var _pendingStakings     : [(Ext.TokenIndex, Types.Staking)] = []; //Pending Staking
  private var pendingStakings             : HashMap.HashMap<Ext.TokenIndex, Types.Staking> = HashMap.fromIter(_pendingStakings.vals(), 0, Ext.TokenIndex.equal, Ext.TokenIndex.hash);
  
  private stable var _stakings            : [(Ext.TokenIndex, Types.Staking)] = []; //Staking
  private var stakings                    : HashMap.HashMap<Ext.TokenIndex, Types.Staking> = HashMap.fromIter(_stakings.vals(), 0, Ext.TokenIndex.equal, Ext.TokenIndex.hash);

  private stable var _transactions        : [(Nat, Types.Transaction)] = []; //NFT transactions
  private var transactions                : HashMap.HashMap<Nat, Types.Transaction> = HashMap.fromIter(_transactions.vals(), 0, Nat.equal, Nat32.fromNat);

  private stable var _harvestTransactions : [(Nat, Types.HarvestTransaction)] = []; //Harvest transactions
  private var harvestTransactions         : HashMap.HashMap<Nat, Types.HarvestTransaction> = HashMap.fromIter(_harvestTransactions.vals(), 0, Nat.equal, Nat32.fromNat);

  private stable var _pendingHarvests      : [(Nat, Types.HarvestPendingTransaction)] = []; //Harvest transactions
  private var pendingHarvests              : HashMap.HashMap<Nat, Types.HarvestPendingTransaction> = HashMap.fromIter(_pendingHarvests.vals(), 0, Nat.equal, Nat32.fromNat);


  //Data of Tier

  private var _TierData : [(Text)] = Data.getData();


  /*
  * upgrade functions
  */
  system func preupgrade() {
    _stakings             := Iter.toArray(stakings.entries());
    _pendingStakings      := Iter.toArray(pendingStakings.entries());
    _transactions         := Iter.toArray(transactions.entries());
    _harvestTransactions  := Iter.toArray(harvestTransactions.entries());
    _pendingHarvests      := Iter.toArray(pendingHarvests.entries());
  };

  system func postupgrade() {
    _stakings             := [];
    _pendingStakings      := [];
    _transactions         := [];
    _harvestTransactions  := [];
    _pendingHarvests       := [];
  };
//Admin function
  // public func isAdmin(p : Principal) : async Bool {
  //     for (a in admins.vals()) {
  //         if (a == p) { return true; };
  //     };
  //     false;
  // };

  ////////////////
  // Heartbeat //
  //////////////


  system func heartbeat() : async () {
      if (not s_heartbeatOn) return;

      // Limit heartbeats
      let now = Time.now();
      if (now - s_heartbeatLastBeat < s_heartbeatIntervalSeconds * 1_000_000_000) return;
      s_heartbeatLastBeat := now;
      try{
        await cronUpdateEarned();
        await processPendingHarvest();//Send payment 
      }catch(e){
        //Nothing
      }
      // Run jobs
      // await _MarketPlace.cronDisbursements();
      // await _MarketPlace.cronSettlements();
  };


  public shared ({ caller }) func updatePool(request: Types.StakingPool) : async Result.Result<(), Ext.CommonError> {
      assert(caller == creator);
      _stakingPool := request;
      #ok();
  };
  public shared ({ caller }) func heartbeatSetInterval (
      i : Nat
  ) : async () {
      assert(caller == creator);
      s_heartbeatIntervalSeconds := i;
  };
  //Set minimum harvest
  public shared ({ caller }) func setMinimumTokenHarvest (
      i : Nat
  ) : async () {
      assert(caller == creator);
      _minimumHarvest := i;
  };

  public shared ({ caller }) func heartbeatSwitch (
      on : Bool
  ) : async () {
      assert(caller == creator);
      s_heartbeatOn := on;
  };
  public query func poolInfo() : async Types.StakingPool {
      _stakingPool;
  };

//Get my stats
public query func poolStats(address: Ext.AccountIdentifier) : async Types.PoolStats {
    var _myStaked : Nat = 0;
    var _myEarned : Nat64 = 0;
    var _myWeight : Int = 0;
    for ((idx, stake) in stakings.entries()) {
      if(stake.staker == address){
          _myEarned += stake.earned;
          _myStaked += 1;
          _myWeight += Float.toInt(stake.multiply);
      };
    };

    let _poolStats = {
        totalNFTStaked = stakings.size();
        totalRewarded = _totalRewarded;
        totalWeight = _totalWeight;
        staked = _myStaked;
        earned = _myEarned;
        myWeight = _myWeight;
        minimumHarvest = _minimumHarvest;
        intvalProcess = s_heartbeatIntervalSeconds;
        lastProcessTime = s_heartbeatLastBeat;
        cycles = Cycles.balance();
    };
   
    _poolStats;
};

  //Show Cycles
  public query func getHeartbeatStatus() : async Bool {
     s_heartbeatOn;
  };

  //Show Cycles
  public query func getCycles() : async Text {
    Nat.toText(Cycles.balance());
  };
  //Show all stakings
  public query func getStakings() : async Types.StakingResponse {
    Iter.toArray(stakings.entries());
  };
  //Pending stakings
  public query func getPendingStakings() : async Types.StakingResponse {
    Iter.toArray(pendingStakings.entries());
  };

  public shared ({ caller }) func getCurrentSubaccount(): async Result.Result<Nat, Ext.CommonError>{
    #ok(_nextSubAccount);
  };
  public shared ({ caller }) func getStakeAddress() : async Result.Result<Text, Ext.CommonError>{
      _nextSubAccount += 1;
      let subaccount = Functions.getNextSubAccount(_nextSubAccount);
      let stakeAddress : Ext.AccountIdentifier = AccountBlob.toText(AccountBlob.fromPrincipal(cid, ?subaccount));
      #ok(stakeAddress);
  };

//Harvest
public shared ({ caller }) func harvest(request: Types.HarvestRequest) : async Result.Result<Nat, Ext.CommonError>  {
    let staker = AccountBlob.toText(AccountBlob.fromPrincipal(caller, request.from_subaccount));
    var _processNum : Nat = 0;
    label queue for ((idx, stake) in stakings.entries()) {
        if(stake.staker == staker){
            ignore await processHarvest(idx, stake); //Process harvest.
            _processNum += 1;
          //tokens := Array.append(tokens, [(idx, stake)]);
        };
    };
    #ok(_processNum);
};

  //Staking
  public shared ({ caller }) func stake (
        request : Types.StakeRequest,
    ) : async Result.Result<Text, Ext.CommonError> {
    //1. Check time of Pool
    let timeNow = Time.now();
    if(timeNow < _stakingPool.startTime){
      #err(#Other("This Pool is not started!"));
    }else if(timeNow > _stakingPool.endTime){
      #err(#Other("This Pool has been ended!"));
    }else{
      //Decode token
      let index = switch (Ext.TokenIdentifier.decode(request.token)) {
          case (#err(_)) { return #err(#InvalidToken(request.token)); };
          case (#ok(_, tokenIndex)) { tokenIndex; };
      };
      let staker = AccountBlob.toText(AccountBlob.fromPrincipal(caller, request.from_subaccount));
      _nextSubAccount += 1;
      let subaccount = Functions.getNextSubAccount(_nextSubAccount);
      let stakeAddress : Ext.AccountIdentifier = AccountBlob.toText(AccountBlob.fromPrincipal(cid, ?subaccount));

      //get Multiplier from Tier data 
      let _tier = _TierData.get(Nat32.toNat(index));
      let _multiply = Data.getMultiply(_tier);
      //Add to pending
      pendingStakings.put(index, {
        stakeAddress = stakeAddress;
        stakeSubAccount = _nextSubAccount;
        staker = staker;
        principal = caller;
        stakeTime = Time.now();
        harvestTime = Time.now();
        earned = 0;
        multiply = _multiply; //Depend on NRI, Tier...etc
      });

      #ok(stakeAddress);
    };
    
  };

  //Settle - Finalyze staking
  public shared ({ caller: Principal}) func settle(request : Types.StakeRequest ) : async Result.Result<Ext.AccountIdentifier, Ext.CommonError> {
       // Decode token index from token identifier.
      let index : Ext.TokenIndex = switch (_unpackTokenIdentifier(request.token)) {
          case (#ok(i)) i;
          case (#err(e)) {
              return #err(e);
          };
      };

       // Retrieve the pending transaction.
      let staking = switch (pendingStakings.get(index)) {
          case (?t) t;
          case _ {
              return #err(#Other("No such pending staking."));
          }
      };
      let stakeAddress = staking.stakeAddress;
      // Check the balance of current staking address, ensure this address has been receive the NFT transfer.
      switch (await NFTCanister.bearer(request.token)) {
                case (#ok(owner)){
                  if(AccountIdentifier.fromText(owner) == stakeAddress){
                    stakings.put(index, staking);
                    
                    _totalWeight += Float.toInt(staking.multiply); //This is increase weight of pool, do not forget.

                    pendingStakings.delete(index);
                    //3. Write transaction
                    transactions.put(_tranIdx, {
                      token   = request.token;
                      from    = staking.staker;
                      account = staking.stakeSubAccount;
                      to      = stakeAddress;
                      method  = "Stake";
                      time    = Time.now();
                    });
                    _tranIdx += 1;

                    #ok(owner);
                   }else{
                    #err(#Other("Not holding"));
                   }
                };
                case (#err(e)) #err(e);
            };


      // let _bearer = AccountIdentifier.toText(balance);
      // if(_bearer == staking.stakeAddress){//Received
      //     //Moving to stakings
      //     stakings.put(index, staking);
      //     pendingStakings.delete(index);
      //     #ok();
      // }else{
      //   #err(#Other("Not received!"));
      // }
  };

  // public shared({ caller }) func tokenTransfer (to: Principal, amount: Nat) : async Result.Result<Nat, Ext.CommonError>{
  //     assert(caller == creator);
  //     // await transferToken(to, amount);
  // };

  public shared ({ caller }) func safeTransfer (
    token: Ext.TokenIdentifier,
    from_subaccount: Nat,
    to: Ext.AccountIdentifier,
  ) : async Result.Result<(), Ext.CommonError>{
      assert(caller == creator);
 let index = switch (Ext.TokenIdentifier.decode(token)) {
              case (#err(_)) { return #err(#InvalidToken(token)); };
              case (#ok(_, tokenIndex)) { tokenIndex; };
          };
      let subaccount = Functions.getNextSubAccount(from_subaccount);
      let stakeAddress : Ext.AccountIdentifier = AccountBlob.toText(AccountBlob.fromPrincipal(cid, ?subaccount));

      let _transfer = await NFTCanister.transfer({
                to = #address(to);
                from = #address(stakeAddress);
                subaccount = subaccount;//Sent from stake address subaccount
                token = token;
                notify = false;
                memo = Blob.fromArray([]:[Nat8]);
                amount = 1;
              });
      stakings.delete(index);
      #ok();   
  };

  public shared ({ caller }) func unStake (
      request : Types.StakeRequest
  ) : async Result.Result<(), Ext.CommonError>{
    let index = switch (Ext.TokenIdentifier.decode(request.token)) {
              case (#err(_)) { return #err(#InvalidToken(request.token)); };
              case (#ok(_, tokenIndex)) { tokenIndex; };
          };
    let staker = AccountBlob.toText(AccountBlob.fromPrincipal(caller, request.from_subaccount));

    switch (stakings.get(index)) {
        case (?staking){
            if(staking.staker == staker){
              //1. Transfer back to staker
              let subaccount = Functions.getNextSubAccount(staking.stakeSubAccount);
              switch(await NFTCanister.transfer({
                to          = #address(staker);
                from        = #address(staking.stakeAddress);
                subaccount  = subaccount;//Sent from stake address subaccount
                token       = request.token;
                notify      = false;
                memo        = Blob.fromArray([]:[Nat8]);
                amount      = 1;
              })){
                case (#err(_)){
                  return #err(#Other("An error occurred while transferring NFT"));
                };
                case (#ok(_)){
                //2. Delete staking list
                stakings.delete(index);

                _totalWeight -= Float.toInt(staking.multiply); //This is increase weight of pool, do not forget.

                //3. Write transaction
                transactions.put(_tranIdx, {
                  token   = request.token;
                  from    = staking.stakeAddress;
                  account = staking.stakeSubAccount;
                  to      = staking.staker;
                  method  = "Unstake";
                  time    = Time.now();
                });

                //4. Add earned to pendingHarvest - Use transIdx from transaction to referer
                if(Nat64.toNat(staking.earned) >= _minimumHarvest){
                    pendingHarvests.put(_tranIdx, {
                          from    = cid;//Send from canister pool
                          to      = staking.principal;
                          time    = Time.now();
                          amount  = Nat64.toNat(staking.earned);
                    });
                };
                
                //5. Increase transid
                _tranIdx += 1;

                return #ok();
                }
              }
            }else{
              return #err(#Other("Unauthorized"));
            }
        };
        case _ #err(#Other("No such stakings."));
    };
  };

//Get transactions
public query func getTrans () : async Types.TransactionResponse {
    Iter.toArray(transactions.entries());
};

//Get Pool Balance
public shared ({ caller }) func currentTime () : async Time.Time {
    Time.now();
};
//Get Pool Balance
public shared ({ caller }) func getBalance () : async Nat {
    await TokenCanister.balanceOf(cid);
};

//Get harvest transaction
public query func getHarvestTrans () : async Types.HarvestTransactionResponse {
    Iter.toArray(harvestTransactions.entries());
};

//Get harvest pending transaction
public query func getPendingHarvestTrans () : async Types.HarvestPendingResponse {
    Iter.toArray(pendingHarvests.entries());
};
//Get my stake
public query func getMyStakings(address: Ext.AccountIdentifier) : async Types.StakingResponse {
    var tokens : [(Ext.TokenIndex, Types.Staking)] = [];
    for ((idx, stake) in stakings.entries()) {
        if(stake.staker == address){
            tokens := Array.append(tokens, [(idx, stake)]);
        };
    };
    tokens;
};

// Get index from EXT token identifier.
func _unpackTokenIdentifier (
    token : Ext.TokenIdentifier,
) : Result.Result<Ext.TokenIndex, Ext.CommonError> {
    switch (Ext.TokenIdentifier.decode(token)) {
        case (#ok(principal, tokenIndex)) {
              #ok(tokenIndex);
        };
        case (#err(_)) { return #err(#InvalidToken(token)); };
    };
};

private func cronUpdateEarned () : async () {
      s_heartbeatLastBeat := Time.now();
    label queue for ((index, staking) in stakings.entries()) {
          ignore await calculateEarning(index, staking); //Caculate to distribute -> earned
      };
  };

private func calculateEarning (index: Ext.TokenIndex, staking: Types.Staking): async () {
  let timeNow = Time.now();
  let stakedSecond = timeNow-staking.harvestTime;

  //Check pool active time.
  if(timeNow < _stakingPool.startTime) return;//
  if(timeNow > _stakingPool.endTime) return;//

  //Checking condition
  if(stakedSecond < s_heartbeatIntervalSeconds*1_000_000_000) return;
  //if(_totalWeight <= 0 or _stakingPool.rewardPerSecond <= 0) return;//Check before add earned, make sure Pool active
  let earnedPerSecond = (Float.toInt(staking.multiply)*_stakingPool.rewardPerSecond)/_totalWeight;
  let earnedInBlock: Int = (stakedSecond/1_000_000_000)*earnedPerSecond;

// if(Nat64.toNat(Nat64.fromIntWrap(earnedInBlock)) < _minimumHarvest) return; //Accept minimum token to harvest
  let totalEarned  = staking.earned + Nat64.fromIntWrap(earnedInBlock);
  
  //3. Update record.
  stakings.put(index, {
                stakeAddress = staking.stakeAddress;
                stakeSubAccount = staking.stakeSubAccount;
                staker = staking.staker;
                principal = staking.principal;
                stakeTime = staking.stakeTime;
                harvestTime = timeNow;
                earned = totalEarned;
                multiply = staking.multiply; //Depend on NRI, Tier...etc
              });
  //Update total rewarded
  _totalRewarded += Nat64.fromIntWrap(earnedInBlock);

};

//force process when user harvest
private func processHarvest (index: Ext.TokenIndex, staking: Types.Staking): async () {
  let timeNow = Time.now();
  let stakedSecond = timeNow-staking.harvestTime;

  let earnedPerSecond = (Float.toInt(staking.multiply)*_stakingPool.rewardPerSecond)/_totalWeight;
  // let earnedInBlock = Int.abs(Float.toInt(Float.floor((stakedSecond/1_000_000_000)*earnedPerSecond)));
  // let earnedPerSecond = (staking.multiply*_stakingPool.rewardPerSecond)/_totalWeight;
  let earnedInBlock: Int = (stakedSecond/1_000_000_000)*earnedPerSecond;

  if(Nat64.toNat(Nat64.fromIntWrap(earnedInBlock)) >= _minimumHarvest){
    let totalEarned  = staking.earned + Nat64.fromIntWrap(earnedInBlock);
    
    // let earnedInBlock = Float.fromInt((stakedSecond/1_000_000_000)*earnedPerSecond);
    // let totalEarned  = staking.earned + Nat64.fromIntWrap(Float.toInt(Float.floor(earnedInBlock)));


    //3. Update record.
    stakings.put(index, {
                  stakeAddress = staking.stakeAddress;
                  stakeSubAccount = staking.stakeSubAccount;
                  staker = staking.staker;
                  principal = staking.principal;
                  stakeTime = staking.stakeTime;
                  harvestTime = timeNow;
                  earned = 0; //Reset earned when harvest
                  multiply = staking.multiply; //Depend on NRI, Tier...etc
                });
    //Update total rewarded
    _totalRewarded += Nat64.fromIntWrap(earnedInBlock);

    //4. Add earned to pendingHarvest - Use transIdx from transaction to referer
      pendingHarvests.put(_tranIdx, {
            from    = cid;//Send from canister pool
            to      = staking.principal;
            time    = timeNow;
            amount  = Nat64.toNat(totalEarned);
      });
      //5. Increase transid
      _tranIdx += 1;
  }
};

var lastHarvestCron : Int = 0;
var harvestInterval : Int = 60_000_000_000;

private func processPendingHarvest(): async (){
   let now = Time.now();
    if (now - lastHarvestCron < harvestInterval) return;
    lastHarvestCron := now;
  //label queue 
    label queue for ((txId, harvest) in pendingHarvests.entries()) {
        ignore await transferToken(txId, harvest);
    };
};
//Important Function - Transfer Token to receipts
private func transferToken(txId: Nat, harvest: Types.HarvestPendingTransaction): async Result.Result<Nat, Ext.CommonError>{
    switch(await TokenCanister.transfer(harvest.to, harvest.amount)){
      case(#Ok(transId)){
        //Delete Pending, Add Transaction
        pendingHarvests.delete(txId);
        harvestTransactions.put(txId, {
            from    = cid;//Send from canister pool
            to      = harvest.to;
            time    = Time.now();
            amount  = harvest.amount;
            tokenTx = transId;
        });
        #ok(transId);
      };
      case(#Err(e)) {
        switch (e) {
            case (#AmountTooSmall){
                 #err(#Other("AmountTooSmall"));
            };
            case (#BlockUsed){
                 #err(#Other("BlockUsed"));
            };
            case (#ErrorOperationStyle){
                 #err(#Other("ErrorOperationStyle"));
            };
            case (#ErrorTo){
                 #err(#Other("ErrorTo"));
            };
            case (#InsufficientAllowance){
                 #err(#Other("InsufficientAllowance"));
            };
            case (#InsufficientBalance){
                 #err(#Other("InsufficientBalance"));
            };
            case (#LedgerTrap){
                 #err(#Other("LedgerTrap"));
            };
            case (#Other(m)){
                 #err(#Other("Other: " # m));
            };
            case (#Unauthorized){
                 #err(#Other("Unauthorized"));
            };
        };
      };
    };
};

};
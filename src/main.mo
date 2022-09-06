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

import Option "mo:base/Option";
import Order "mo:base/Order";
import Blob "mo:base/Blob";
import Bool "mo:base/Bool";
import Nat "mo:base/Nat";
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

shared ({ caller = creator }) actor class CanicNFT(
    cid    : Principal, //This is Principal of this Canister.
) = {

  let NFTCanister : Actor.NFT = actor("mxftc-eyaaa-aaaap-qanga-cai");

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
  private stable var _admins              : [Principal] = [creator];
  private stable var _nextSubAccount      : Nat = 0;
  private stable var _tranIdx             : Nat = 0;
  private stable var _harvestIdx          : Nat = 0;

  // Heartbeat - System cronjob
  private stable var s_heartbeatIntervalSeconds : Nat = 5;//Distribute every 1 minute
  private stable var s_heartbeatLastBeat : Int = 0;
  private stable var s_heartbeatOn : Bool = true;

  // Pool setting
  private stable var _totalWeight : Nat = 0; //This is base on NRI, Tier...
  private stable var _totalRewarded : Nat64 = 0; //Total rewarded counter.



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

  private stable var _pendingHarvests      : [(Nat, Types.HarvestTransaction)] = []; //Harvest transactions
  private var pendingHarvests              : HashMap.HashMap<Nat, Types.HarvestTransaction> = HashMap.fromIter(_pendingHarvests.vals(), 0, Nat.equal, Nat32.fromNat);


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
      await cronUpdateEarned();
      // Run jobs
      // await _MarketPlace.cronDisbursements();
      // await _MarketPlace.cronSettlements();
  };

  //Update Canister Pool
  public shared ({ caller }) func updatePool(request: Types.StakingPool) : async Result.Result<(), Ext.CommonError> {
      // assert(caller == creator);
      _stakingPool := request;
      #ok();
  };
  public shared ({ caller }) func heartbeatSetInterval (
      i : Nat
  ) : async () {
      assert(caller == creator);
      s_heartbeatIntervalSeconds := i;
  };

  public shared ({ caller }) func heartbeatSwitch (
      on : Bool
  ) : async () {
      assert(caller == creator);
      s_heartbeatOn := on;
  };
  public shared ({ caller}) func poolInfo() : async Types.StakingPool {
      _stakingPool;
  };


  public query func stats() : async Nat {
      _totalWeight;
  };

  //Show Cycles
  public query func getCycles() : async Text {
    Nat.toText(Cycles.balance() / 1_000_000_000_000) # "T";
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

  //Staking
  public shared ({ caller }) func stake (
        request : Types.StakeRequest,
    ) : async Result.Result<Text, Ext.CommonError> {
    //Decode token
    let index = switch (Ext.TokenIdentifier.decode(request.token)) {
        case (#err(_)) { return #err(#InvalidToken(request.token)); };
        case (#ok(_, tokenIndex)) { tokenIndex; };
    };
    let staker = AccountBlob.toText(AccountBlob.fromPrincipal(caller, request.from_subaccount));
    _nextSubAccount += 1;
    let subaccount = Functions.getNextSubAccount(_nextSubAccount);
    let stakeAddress : Ext.AccountIdentifier = AccountBlob.toText(AccountBlob.fromPrincipal(cid, ?subaccount));

    //Add to pending
    pendingStakings.put(index, {
      stakeAddress = stakeAddress;
      stakeSubAccount = _nextSubAccount;
      staker = staker;
      principal = caller;
      stakeTime = Time.now();
      harvestTime = Time.now();
      earned = 0;
      multiply = 1; //Depend on NRI, Tier...etc
    });

    #ok(stakeAddress);
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
                    
                    _totalWeight += staking.multiply; //This is increase weight of pool, do not forget.

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

                _totalWeight -= staking.multiply; //This is increase weight of pool, do not forget.

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
                pendingHarvests.put(_tranIdx, {
                      from    = cid;//Send from canister pool
                      to      = staking.principal;
                      time    = Time.now();
                      amount  = staking.earned;
                });

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
//Get harvest transaction
public query func getHarvestTrans () : async Types.HarvestTransactionResponse {
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
          ignore calculateEarning(index, staking); //Caculate to distribute -> earned
      };
  };

private func calculateEarning (index: Ext.TokenIndex, staking: Types.Staking): async () {
  let timeNow = Time.now();
  let stakedSecond = timeNow-staking.harvestTime;
  if(stakedSecond < s_heartbeatIntervalSeconds*1_000_000_000) return;
  if(_totalWeight <= 0 or _stakingPool.rewardPerSecond <= 0) return;//Check before add earned, make sure Pool active
  let earnedPerSecond = (staking.multiply*_stakingPool.rewardPerSecond)/_totalWeight;
  let earnedInBlock: Int = (stakedSecond/1_000_000_000)*earnedPerSecond;
  let totalEarned  = staking.earned + Nat64.fromIntWrap(earnedInBlock);
  
  //Update record.
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
}

};
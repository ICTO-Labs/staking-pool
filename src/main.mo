/**
 * Module     : main.mo
 * Copyright  : 2022 Canister Team
 * License    : Apache 2.0 with LLVM Exception
 * Maintainer : Canister Team <dev@canister.app>
 * Stability  : Experimental
 */

import HashMap "mo:base/HashMap";
import Principal "mo:base/Principal";
import Time "mo:base/Time";
import Iter "mo:base/Iter";
import Array "mo:base/Array";
import Option "mo:base/Option";
import Order "mo:base/Order";
import Nat "mo:base/Nat";
import Nat64 "mo:base/Nat64";
import Result "mo:base/Result";
import Text "mo:base/Text";
import ExperimentalCycles "mo:base/ExperimentalCycles";
import Ext "mo:ext/Ext";
import Types "types";


shared ({ caller = creator }) actor class CanicNFT(
    cid    : Principal, //This is Principal of this Canister.
) = {

  // Admins
  private stable var stableAdmins       : [Principal] = [creator];
  private stable var stableTransactions : [(Ext.TokenIndex, Types.Transaction)] = [];
  private stable var stableStakings               : [(Ext.TokenIndex, Types.Staking)] = []; //Staking


  //Canister Pool
  public shared ({ caller}) func getPid() : async Result.Result<Text, Ext.CommonError> {
      #ok(Principal.toText(cid));
  };


  //Staking
  public shared ({ caller }) func stake (
        request : Types.StakeRequest,
    ) : async Result.Result<(), Ext.CommonError> {
      #ok();
  };

};
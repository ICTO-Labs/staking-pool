import Principal "mo:base/Principal";
import Result "mo:base/Result";
import Time "mo:base/Time";

import Ext "mo:ext/Ext";


module {
    //Staking

    public type StakeRequest = {
        from_subaccount  : ?Ext.SubAccount;
        tokens           : [Ext.TokenIdentifier];
    };

    public type StakingResponse = [(
        Ext.TokenIndex,
        Staking
    )];
    public type Staking = {
        account: Ext.AccountIdentifier;
        principal: Principal;
        stakeTime: Time.Time;
        harvestTime: Time.Time;
        earned: Nat64;
        multiply: Nat; //Depend on NRI, Tier...etc
    };

    public type Transaction = {
        token   : Ext.TokenIdentifier;
        seller  : Principal;
        price   : Nat64;
        buyer   : Ext.AccountIdentifier;
        time    : Time.Time;
    };

}
import Principal "mo:base/Principal";
import Result "mo:base/Result";
import Time "mo:base/Time";
import Nat "mo:base/Nat";
import Nat64 "mo:base/Nat64";
import Nat32 "mo:base/Nat32";

import Ext "mo:ext/Ext";


module {
    //Staking

    public type StakeRequest = {
        from_subaccount  : ?Ext.SubAccount;
        token            : Ext.TokenIdentifier;
    };

    public type HarvestRequest = {
        from_subaccount   : ?Ext.SubAccount;
    };

    public type StakingResponse = [(
        Ext.TokenIndex,
        Staking
    )];
    public type Staking = {
        stakeAddress: Ext.AccountIdentifier;
        stakeSubAccount: Nat;
        staker: Ext.AccountIdentifier;
        principal: Principal;
        stakeTime: Time.Time;
        harvestTime: Time.Time;
        earned: Nat64;
        multiply: Float; //Depend on NRI, Tier...etc
    };

    public type TransactionResponse = [(
        Nat,
        Transaction
    )];

    public type HarvestTransactionResponse = [(
        Nat,
        HarvestTransaction
    )];

    public type HarvestPendingResponse = [(
        Nat,
        HarvestPendingTransaction
    )];

    //NFT transaction - Method: Stake/Unstake
    public type Transaction = {
        // id          : Nat32;
        token       : Ext.TokenIdentifier;
        from        : Ext.AccountIdentifier;
        account     : Nat;//Subaccount of stake address.
        to          : Ext.AccountIdentifier;
        method      : Text;//Stake-Unstake
        time        : Time.Time;
    };

    //Token transaction
    public type HarvestPendingTransaction = {
        from        : Principal;
        to          : Principal;
        amount      : Nat;
        time        : Time.Time;
    };

    //Token transaction
    public type HarvestTransaction = {
        from        : Principal;
        to          : Principal;
        amount      : Nat;
        time        : Time.Time;
        tokenTx     : Nat; //Token transfer receipt ID
    };

    public type StakingPool = {
        name: Text;//Name of Pool
        startTime: Time.Time;
        endTime: Time.Time;
        totalRewards: Nat;//Total Token reward in this pool
        rewardTokenFee : Nat; // Fee when withdraw rewards.

        stakingSymbol: Text; //CANIC NFT
        stakingToken: Text; //Canister of NFT
        stakingStandard: Text; //Ext
        rewardSymbol: Text; //Ex: XCANIC
        rewardToken: Text; //Canister ID
        rewardStandard: Text; // DIP20
        rewardTokenDecimals: Nat;
        rewardPerSecond: Nat; //Calculate by second
    };

    public type PoolStats = {
        totalNFTStaked: Nat;
        totalRewarded: Nat64;
        totalWeight: Int;
        earned: Nat64; //Check earned of user
        staked: Nat; //Check total NFT staked by user
        myWeight: Int; //My Weight
        minimumHarvest: Nat; //Min
        intvalProcess: Nat;
        lastProcessTime: Int;
        cycles: Nat;
    }
}
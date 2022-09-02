import Ext "mo:ext/Ext";
import Text "mo:base/Text";
import Result "mo:base/Result";
import Principal "mo:base/Principal";
import Nat8 "mo:base/Nat8";
import Blob "mo:base/Blob";

module {
    public type SubAccount = Blob;
    public type Memo = Blob;
    public type Account = { address: Text};
    public type User = {
        #address : Ext.AccountIdentifier; //No notification
        #principal : Principal; //defaults to sub account 0
  };
    // Arguments for the `transfer` call.
    public type NftTransferArgs = {
        to: User;
        from: User;
        memo: Memo;
        subaccount: Ext.SubAccount;
        token: Ext.TokenIdentifier;
        notify : Bool;
        amount: Nat; //Always 1 for NFT
    };

    //Check balance
    public type NftBearer = Ext.TokenIdentifier;
    public type NFT = actor {
        // Transfers NFT from .
        transfer : shared (NftTransferArgs) -> async ();
        bearer: shared (NftBearer) -> async Ext.NonFungible.BearerResponse;

    };

}
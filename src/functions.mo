import Nat "mo:base/Nat";
import Nat8 "mo:base/Nat8";
import Array "mo:base/Array";
import AccountBlob "mo:principal/blob/AccountIdentifier";
import Ext "mo:ext/Ext";

module {
    // Convert incrementing sub account to a proper Blob.
    public func natToSubAccount(n : Nat) : Ext.SubAccount {
            let n_byte = func(i : Nat) : Nat8 {
                assert(i < 32);
                let shift : Nat = 8 * (32 - 1 - i);
                Nat8.fromIntWrap(n / 2**shift)
            };
            Array.tabulate<Nat8>(32, n_byte)
    };
    // Get and increment next subaccount.
    public func getNextSubAccount(nextSubAccount: Nat) : Ext.SubAccount {
        var _saOffset = 1000; //Start with 1000+
        return natToSubAccount(_saOffset + nextSubAccount);
    };

}
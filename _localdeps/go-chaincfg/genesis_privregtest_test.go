package chaincfg

import (
	"strings"
	"testing"
)

// TestPrivRegtestGenesisMessage verifies the regtest genesis coinbase carries the priv-chain bsv Japanese
// timestamp ("honour the Japanese genesis message") and that the genesis hash was recomputed from it — i.e.
// it is no longer the upstream 0f9188f1... regtest genesis.
func TestPrivRegtestGenesisMessage(t *testing.T) {
	sig := string(RegressionNetParams.GenesisBlock.Transactions[0].TxIn[0].SignatureScript)
	if !strings.Contains(sig, privGenesisMessage) {
		t.Fatalf("regtest genesis coinbase missing Japanese message %q; scriptSig=%q", privGenesisMessage, sig)
	}
	if RegressionNetParams.GenesisHash.String() == "0f9188f13cb7b2c71f2a335e3a4fc328bf5beb436012afca590b1a11466e2206" {
		t.Fatal("regtest genesis hash is still the upstream genesis; the Japanese coinbase was not applied")
	}
	if RegressionNetParams.GenesisActivationHeight != 1 || RegressionNetParams.ChronicleActivationHeight != 1 {
		t.Fatalf("expected Genesis+Chronicle activation at height 1, got %d/%d",
			RegressionNetParams.GenesisActivationHeight, RegressionNetParams.ChronicleActivationHeight)
	}
	t.Logf("regtest genesis hash=%s; coinbase carries %q; Genesis/Chronicle active at height 1",
		RegressionNetParams.GenesisHash, privGenesisMessage)
}

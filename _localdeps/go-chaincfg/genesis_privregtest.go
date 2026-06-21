// Copyright (c) 2026 priv-chain.
// Use of this source code is governed by an ISC license that can be found in the LICENSE file.

package chaincfg

import (
	"math/big"

	"github.com/bsv-blockchain/go-bt/v2/chainhash"
	"github.com/bsv-blockchain/go-wire"
)

// privGenesisMessage is the priv-chain bitcoin-sv node's genesis coinbase timestamp
// (bitcoin-sv/src/chainparams.cpp). teranode's private regtest honours it so its regtest genesis carries
// the same message as the priv-chain bsv node instead of the upstream "The Times..." mainnet coinbase.
const privGenesisMessage = "フィンテックに危機感 - Nikkei January 3rd, 2026"

// regTestGenesisHash holds the hash of the recomputed private-regtest genesis block. It is filled in by the
// init() below once the Japanese coinbase has been mined into the regtest genesis. RegressionNetParams
// references &regTestGenesisHash (see params.go), so the new value is observed before the params are used.
var regTestGenesisHash chainhash.Hash

// init rebuilds the regtest genesis block with the priv-chain bsv Japanese coinbase message — same 50-BSV
// output script + scriptSig framing as the standard genesis, only the embedded timestamp differs — then
// recomputes the merkle root, mines a valid nonce for the trivial regtest target, and records the resulting
// genesis hash. regTestGenesisBlock is defined in genesis.go; RegressionNetParams points at it and at
// &regTestGenesisHash, so these mutations are reflected wherever the params are consumed.
func init() {
	msg := []byte(privGenesisMessage)
	// scriptSig: PUSH4(ffff001d) PUSH1(04) PUSH(len)(message) — mirrors bitcoin-sv CreateGenesisBlock's
	// CScript() << 486604799 << CScriptNum(4) << <pszTimestamp bytes>.
	sigScript := append([]byte{0x04, 0xff, 0xff, 0x00, 0x1d, 0x01, 0x04, byte(len(msg))}, msg...)

	coinbase := genesisCoinbaseTx // same single 50-BSV output to the genesis pubkey; replace only the input
	coinbase.TxIn = []*wire.TxIn{{
		PreviousOutPoint: wire.OutPoint{Hash: chainhash.Hash{}, Index: 0xffffffff},
		SignatureScript:  sigScript,
		Sequence:         0xffffffff,
	}}

	regTestGenesisBlock.Transactions = []*wire.MsgTx{&coinbase}
	regTestGenesisBlock.Header.MerkleRoot = coinbase.TxHash()
	regTestGenesisBlock.Header.Nonce = 0

	// Mine a valid nonce. regressionPowLimit == 2^255-1, so roughly half of all nonces satisfy the target —
	// this terminates almost immediately.
	for {
		h := regTestGenesisBlock.BlockHash()
		if hashToBig(&h).Cmp(regressionPowLimit) <= 0 {
			break
		}
		regTestGenesisBlock.Header.Nonce++
	}
	regTestGenesisHash = regTestGenesisBlock.BlockHash()
}

// hashToBig converts a little-endian chainhash into its big-endian big.Int value for PoW comparison.
func hashToBig(hash *chainhash.Hash) *big.Int {
	buf := *hash
	for i, j := 0, len(buf)-1; i < j; i, j = i+1, j-1 {
		buf[i], buf[j] = buf[j], buf[i]
	}
	return new(big.Int).SetBytes(buf[:])
}

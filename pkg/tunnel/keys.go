// Key derivation from Pre-Shared Key for the VPN protocol.
//
// From a single PSK string, three independent keys are derived:
//   - masterKey: SHA-256(PSK) — used for HMAC authentication
//   - encKey: SHA-256(masterKey || "encryption") — used for AES-256-GCM
//   - obfsKey: DeriveObfsKey(SHA-256(masterKey || "obfuscation")) — used for ChaCha20 obfuscation
package tunnel

import (
	"crypto/sha256"
	"log"

	vpncrypto "simplevpn/pkg/crypto"
	"simplevpn/pkg/obfs"
)

// Keys holds all cryptographic material derived from a PSK.
type Keys struct {
	Master  [32]byte
	Enc     [32]byte
	Obfs    [32]byte
	Cipher  *vpncrypto.Cipher
	Obfuscator *obfs.Obfuscator
}

// DeriveKeys derives all cryptographic keys and initializes cipher/obfuscator from a PSK.
func DeriveKeys(psk string) (*Keys, error) {
	k := &Keys{}
	k.Master = sha256.Sum256([]byte(psk))
	k.Enc = sha256.Sum256(append(k.Master[:], []byte("encryption")...))
	obfsRaw := sha256.Sum256(append(k.Master[:], []byte("obfuscation")...))
	k.Obfs = obfs.DeriveObfsKey(obfsRaw)

	ciph, err := vpncrypto.NewCipherFromKey(k.Enc)
	if err != nil {
		return nil, err
	}
	k.Cipher = ciph
	k.Obfuscator = obfs.New(k.Obfs)

	log.Printf("[tunnel] Keys derived: encryption=AES-256-GCM, obfuscation=ChaCha20")
	return k, nil
}

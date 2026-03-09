// Key derivation from server key for the VPN protocol.
//
// From a single server key string, three independent keys are derived:
//   - masterKey: SHA-256(serverKey) — used for tunnel encryption key derivation
//   - encKey: SHA-256(masterKey || "encryption") — used for AES-256-GCM
//   - obfsKey: DeriveObfsKey(SHA-256(masterKey || "obfuscation")) — used for ChaCha20 obfuscation
package tunnel

import (
	"crypto/sha256"
	"log"

	vpncrypto "simplevpn/pkg/crypto"
	"simplevpn/pkg/obfs"
)

// Keys holds all cryptographic material derived from a server key.
type Keys struct {
	Master     [32]byte
	Enc        [32]byte
	Obfs       [32]byte
	Cipher     *vpncrypto.Cipher
	Obfuscator *obfs.Obfuscator
}

// DeriveKeys derives all cryptographic keys and initializes cipher/obfuscator from a server key.
func DeriveKeys(serverKey string) (*Keys, error) {
	k := &Keys{}
	k.Master = sha256.Sum256([]byte(serverKey))
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

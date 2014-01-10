#!/usr/bin/python

# bitcoin midstate and Avalon init value calculation, copyright by Frank Buss

# some helper functions are from https://github.com/bitcoin/bitcoin/blob/master/contrib/pyminer/pyminer.py
# SHA256 implementation as described in the pseudo code at http://en.wikipedia.org/wiki/SHA-2

from struct import pack, unpack
from binascii import unhexlify, hexlify

# initialize array of round constants
K = [
	0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
	0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
	0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
	0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
	0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
	0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
	0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
	0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
]

def bytereverse(x):
	return uint32(( ((x) << 24) | (((x) << 8) & 0x00ff0000) |
					(((x) >> 8) & 0x0000ff00) | ((x) >> 24) ))

def uint32(x):
	return x & 0xffffffff

def rotateright(i,p):
    """i>>>p"""
    p &= 0x1F # p mod 32
    return i>>p | ((i<<(32-p)) & 0xFFFFFFFF)

def rotateleft(i,p):
    """i<<<p"""
    p &= 0x1F # p mod 32
    return ((i<<p) & 0xFFFFFFFF) | ((i>>(32-p)) & 0xFFFFFFFF)

def shiftright(i,p):
    """i>>p"""
    p &= 0x1F # p mod 32
    return i>>p

def addu32(*i):
    return sum(list(i))&0xFFFFFFFF

def CH(e, f, g):
	return (e & f) ^ ((~e) & g)

def E0(a):
	return rotateright(a, 2) ^ rotateright(a, 13) ^ rotateright(a, 22)

def E1(e):
	return rotateright(e, 6) ^ rotateright(e, 11) ^ rotateright(e, 25)

def SIG0(x):
	return rotateright(x, 7) ^ rotateright(x, 18) ^ shiftright(x, 3)

def SIG1(x):
	return rotateright(x, 17) ^ rotateright(x, 19) ^ shiftright(x, 10)

def MAJ(a, b, c):
	return (a & b) ^ (a & c) ^ (b & c)

def calculateAvalonHashData(datastr):
	# convert to binary array
	data = unhexlify(datastr)

	# initialize hash values
	h0 = 0x6a09e667
	h1 = 0xbb67ae85
	h2 = 0x3c6ef372
	h3 = 0xa54ff53a
	h4 = 0x510e527f
	h5 = 0x9b05688c
	h6 = 0x1f83d9ab
	h7 = 0x5be0cd19

	# copy chunk into first 16 words w[0..15] of the message schedule array
	w = list(unpack('<IIIIIIIIIIIIIIII', data[:64]))

	# extend the first 16 words into the remaining 48 words w[16..63] of the message schedule array:
	w += [0] * 48
	for i in range(16, 64):
		w[i] = addu32(SIG1(w[i-2]), w[i-7], SIG0(w[i-15]), w[i-16])

	# initialize working variables to current hash value
	a = h0
	b = h1
	c = h2
	d = h3
	e = h4
	f = h5
	g = h6
	h = h7

	# compression function main loop
	for i in range(64):
		t1 = addu32(h, E1(e), CH(e,f,g), K[i], w[i])
		t2 = addu32(E0(a), MAJ(a,b,c))
		h = g
		g = f
		f = e
		e = addu32(d, t1)
		d = c
		c = b
		b = a
		a = addu32(t1, t2)
		if i == 0: a0 = a
		if i == 1: a1 = a
		if i == 2: a2 = a
		if i == 0: e0 = e
		if i == 1: e1 = e
		if i == 2: e2 = e

	# add the compressed chunk to the current hash value:
	h0 = addu32(h0, a)
	h1 = addu32(h1, b)
	h2 = addu32(h2, c)
	h3 = addu32(h3, d)
	h4 = addu32(h4, e)
	h5 = addu32(h5, f)
	h6 = addu32(h6, g)
	h7 = addu32(h7, h)
	
	# midstate
	midstate = [h0, h1, h2, h3, h4, h5, h6, h7]
	
	# little endian / big endian ?
	if False:
		for i in range(8):
			midstate[i] = bytereverse(midstate[i])

	# extract first three words of second chunk
	chunk2start = list(unpack('<III', data[64:76]))
	if False:
		a0 = bytereverse(a0)
		a1 = bytereverse(a1)
		a2 = bytereverse(a2)
		e0 = bytereverse(e0)
		e1 = bytereverse(e1)
		e2 = bytereverse(e2)
	
	# build and return array
	return chunk2start + [a1, a0, e2, e1, e0] + midstate + [a2]

	# bitcoin block struct:
	#   int nVersion;
	#   uint256 hashPrevBlock;
	#   uint256 hashMerkleRoot;
	#   unsigned int nTime;
	#   unsigned int nBits;
	#   unsigned int nNonce;

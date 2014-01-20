# good explanation how mining and pools are working:
# https://github.com/sinisterchipmunk/bitpool/wiki/Bitcoin-Mining-Pool-Developer's-Reference

# derived from https://github.com/bitcoin/bitcoin/blob/master/contrib/pyminer/pyminer.py and ported from Python 2 to Python 3

import time
from hashlib import sha256
import struct
from binascii import unhexlify, hexlify
from avalonHashData import calculateAvalonHashData
import json
import pprint
import hashlib
import re
import base64
import http.client
import sys

ERR_SLEEP = 15

def uint32(x):
	return x & 0xffffffff

def bytereverse(x):
	return uint32(( ((x) << 24) | (((x) << 8) & 0x00ff0000) |
					(((x) >> 8) & 0x0000ff00) | ((x) >> 24) ))

def bufreverse(in_buf):
	out_words = []
	for i in range(0, len(in_buf), 4):
			word = struct.unpack('@I', in_buf[i:i+4])[0]
			out_words.append(struct.pack('@I', bytereverse(word)))
	return b''.join(out_words)

def wordreverse(in_buf):
	out_words = []
	for i in range(0, len(in_buf), 4):
			out_words.append(in_buf[i:i+4])
	out_words.reverse()
	return b''.join(out_words)
		
# test if a nonce results in a hash less than the required target
def testNonce(datastr, targetstr, nonce):
	# decode work data hex string to binary
	static_data = unhexlify(datastr)
	static_data = bufreverse(static_data)

	# the first 76b of 80b do not change
	blk_hdr = static_data[:76]
	
	# add nonce
	blk_hdr += struct.pack("<I", nonce)

	# hash first 80b of block header
	static_hash = sha256()
	static_hash.update(blk_hdr)

	# sha256 hash of sha256 hash
	hash_o = sha256()
	hash_o.update(static_hash.digest())
	hash = hash_o.digest()

	# convert binary hash to 256-bit Python long
	hash = bufreverse(hash)
	hash = wordreverse(hash)

	hash_str = hexlify(hash)
	l = int(hash_str, 16)

	# decode 256-bit target value
	targetbin = unhexlify(targetstr)
	targetbin = targetbin[::-1]        # byte-swap and dword-swap
	targetbin_str = hexlify(targetbin)
	target = int(targetbin_str, 16)

	# proof-of-work test:  hash < target
	return l < target
		

def rpc(method, params=None):
	#username = "1F4Rn4CmNtnhcZrVTrp2QBriWWZct3iPnB"
	#password = "pass"
	authpair = "%s:%s" % (username, password)
	authhdr = "Basic %s" % (base64.b64encode(authpair.encode()).decode())
	OBJID = 1
	obj = { 'method' : method, 'id' : 'json' }
	if params is None:
		obj['params'] = []
	else:
		obj['params'] = params
	conn.request('POST', '/', json.dumps(obj), { 'Authorization' : authhdr, 'Content-type' : 'application/json' })
	resp = conn.getresponse()
	if resp is None:
		print("JSON-RPC: no response")
		return None

	body = resp.read()
	resp_obj = json.loads(body.decode())
	if resp_obj is None:
		print("JSON-RPC: cannot JSON-decode body")
		return None
	if 'error' in resp_obj and resp_obj['error'] != None:
		return resp_obj['error']
	if 'result' not in resp_obj:
		print("JSON-RPC: no result in object")
		return None
	#print(resp_obj['result'])
	return resp_obj['result']

# get new work
def getwork():
	work = rpc('getwork')
	if work is None:
		time.sleep(ERR_SLEEP)
		return
	if 'data' not in work or 'target' not in work:
		time.sleep(ERR_SLEEP)
		return
	return (work['data'], work['target'])

# submit work	
def submitWork(original_data, nonce):
	nonce = hexlify(struct.pack(">I", nonce)).decode()
	solution = original_data[:152] + nonce + original_data[160:256]
	param_arr = [ solution ]
	result = rpc('getwork', param_arr)
	print(time.asctime(), "--> Upstream RPC result:", result)

# connect to mining pool	
def bitcoinConnect(_username, _password, server):
	global conn, username, password
	username = _username
	password = _password
	print("connecting to:", server)
	conn = http.client.HTTPConnection(server, timeout=10)
	#conn.set_debuglevel(1)


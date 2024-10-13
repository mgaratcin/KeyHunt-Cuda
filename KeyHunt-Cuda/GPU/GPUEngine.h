/*
 * This file is part of the VanitySearch distribution (https://github.com/JeanLucPons/VanitySearch).
 * Copyright (c) 2019 Jean Luc PONS.
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, version 3.
 *
 * This program is distributed in the hope that it will be useful, but
 * WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
 * General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <http://www.gnu.org/licenses/>.
*/

#ifndef GPUENGINEH
#define GPUENGINEH

#include <vector>
#include "../SECP256k1.h"

#define SEARCH_COMPRESSED 0
#define SEARCH_UNCOMPRESSED 1
#define SEARCH_BOTH 2

// operating mode
#define SEARCH_MODE_MA 1	// multiple addresses
#define SEARCH_MODE_SA 2	// single address
#define SEARCH_MODE_MX 3	// multiple xpoints
#define SEARCH_MODE_SX 4	// single xpoint

#define COIN_BTC 1
#define COIN_ETH 2

// Number of key per thread (must be a multiple of GRP_SIZE) per kernel call
#define STEP_SIZE ((__uint128_t)2048000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000 * (__uint128_t)2048000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000)

// Number of thread per block
#define ITEM_SIZE_A 28
#define ITEM_SIZE_A32 (ITEM_SIZE_A/4)

#define ITEM_SIZE_X 40
#define ITEM_SIZE_X32 (ITEM_SIZE_X/4)

typedef struct {
	__uint128_t thId;
	__uint128_t  incr;
	__uint128_t* hash;
	bool mode;
} ITEM;

class GPUEngine
{

public:

	GPUEngine(Secp256K1* secp, int nbThreadGroup, int nbThreadPerGroup, int gpuId, uint32_t maxFound, 
		int searchMode, int compMode, int coinType, __uint128_t BLOOM_SIZE, __uint128_t BLOOM_BITS, 
		__uint128_t BLOOM_HASHES, const __uint128_t* BLOOM_DATA, __uint128_t* DATA, uint64_t TOTAL_COUNT, bool rKey);

	GPUEngine(Secp256K1* secp, int nbThreadGroup, int nbThreadPerGroup, int gpuId, uint32_t maxFound, 
		int searchMode, int compMode, int coinType, const __uint128_t* hashORxpoint, bool rKey);

	~GPUEngine();

	bool SetKeys(Point* p);

	bool LaunchSEARCH_MODE_MA(std::vector<ITEM>& dataFound, bool spinWait = false);
	bool LaunchSEARCH_MODE_SA(std::vector<ITEM>& dataFound, bool spinWait = false);
	bool LaunchSEARCH_MODE_MX(std::vector<ITEM>& dataFound, bool spinWait = false);
	bool LaunchSEARCH_MODE_SX(std::vector<ITEM>& dataFound, bool spinWait = false);

	int GetNbThread();
	int GetGroupSize();

	//bool Check(Secp256K1 *secp);
	std::string deviceName;

	static void PrintCudaInfo();
	static void GenerateCode(Secp256K1* secp, int size);

private:
	void InitGenratorTable(Secp256K1* secp);

	bool callKernelSEARCH_MODE_MA();
	bool callKernelSEARCH_MODE_SA();
	bool callKernelSEARCH_MODE_MX();
	bool callKernelSEARCH_MODE_SX();

	int CheckBinary(const uint8_t* x, int K_LENGTH);

	int nbThread;
	int nbThreadPerGroup;

	__uint128_t* inputHashORxpoint;
	__uint128_t* inputHashORxpointPinned;

	//uint8_t *bloomLookUp;
	__uint128_t* inputBloomLookUp;
	__uint128_t* inputBloomLookUpPinned;

	__uint128_t* inputKey;
	__uint128_t* inputKeyPinned;

	__uint128_t* outputBuffer;
	__uint128_t* outputBufferPinned;

	__uint128_t* __2Gnx;
	__uint128_t* __2Gny;

	__uint128_t* _Gx;
	__uint128_t* _Gy;

	bool initialised;
	uint32_t compMode;
	uint32_t searchMode;
	uint32_t coinType;
	bool littleEndian;

	bool rKey;
	uint64_t maxFound;
	__uint128_t outputSize;

	__uint128_t BLOOM_SIZE;
	__uint128_t BLOOM_BITS;
	__uint128_t BLOOM_HASHES;

	__uint128_t* DATA;
	__uint128_t TOTAL_COUNT;

};

#endif // GPUENGINEH

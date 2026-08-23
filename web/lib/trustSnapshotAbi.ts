// Generated from contracts/out/TrustSnapshot.sol/TrustSnapshot.json. Do not hand edit.
// Regenerate with: bash scripts/gen_abi.sh

export const trustSnapshotAbi = [
  {
    type: "function",
    name: "MAX_SCORE",
    inputs: [],
    outputs: [
      {
        name: "",
        type: "uint16",
        internalType: "uint16",
      },
    ],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "acceptOwnership",
    inputs: [],
    outputs: [],
    stateMutability: "nonpayable",
  },
  {
    type: "function",
    name: "latest",
    inputs: [],
    outputs: [
      {
        name: "",
        type: "tuple",
        internalType: "struct TrustSnapshot.Snapshot",
        components: [
          {
            name: "merkleRoot",
            type: "bytes32",
            internalType: "bytes32",
          },
          {
            name: "computedAt",
            type: "uint64",
            internalType: "uint64",
          },
          {
            name: "agentCount",
            type: "uint32",
            internalType: "uint32",
          },
          {
            name: "payloadURI",
            type: "string",
            internalType: "string",
          },
        ],
      },
    ],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "leaf",
    inputs: [
      {
        name: "agentId",
        type: "uint256",
        internalType: "uint256",
      },
      {
        name: "liveness",
        type: "uint16",
        internalType: "uint16",
      },
      {
        name: "trust",
        type: "uint16",
        internalType: "uint16",
      },
      {
        name: "confidence",
        type: "uint16",
        internalType: "uint16",
      },
      {
        name: "computedAt",
        type: "uint64",
        internalType: "uint64",
      },
    ],
    outputs: [
      {
        name: "",
        type: "bytes32",
        internalType: "bytes32",
      },
    ],
    stateMutability: "pure",
  },
  {
    type: "function",
    name: "owner",
    inputs: [],
    outputs: [
      {
        name: "",
        type: "address",
        internalType: "address",
      },
    ],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "pendingOwner",
    inputs: [],
    outputs: [
      {
        name: "",
        type: "address",
        internalType: "address",
      },
    ],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "publish",
    inputs: [
      {
        name: "merkleRoot",
        type: "bytes32",
        internalType: "bytes32",
      },
      {
        name: "agentCount",
        type: "uint32",
        internalType: "uint32",
      },
      {
        name: "computedAt",
        type: "uint64",
        internalType: "uint64",
      },
      {
        name: "payloadURI",
        type: "string",
        internalType: "string",
      },
    ],
    outputs: [
      {
        name: "id",
        type: "uint256",
        internalType: "uint256",
      },
    ],
    stateMutability: "nonpayable",
  },
  {
    type: "function",
    name: "publishers",
    inputs: [
      {
        name: "",
        type: "address",
        internalType: "address",
      },
    ],
    outputs: [
      {
        name: "",
        type: "bool",
        internalType: "bool",
      },
    ],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "renounceOwnership",
    inputs: [],
    outputs: [],
    stateMutability: "nonpayable",
  },
  {
    type: "function",
    name: "setPublisher",
    inputs: [
      {
        name: "publisher",
        type: "address",
        internalType: "address",
      },
      {
        name: "allowed",
        type: "bool",
        internalType: "bool",
      },
    ],
    outputs: [],
    stateMutability: "nonpayable",
  },
  {
    type: "function",
    name: "snapshotCount",
    inputs: [],
    outputs: [
      {
        name: "",
        type: "uint256",
        internalType: "uint256",
      },
    ],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "snapshots",
    inputs: [
      {
        name: "",
        type: "uint256",
        internalType: "uint256",
      },
    ],
    outputs: [
      {
        name: "merkleRoot",
        type: "bytes32",
        internalType: "bytes32",
      },
      {
        name: "computedAt",
        type: "uint64",
        internalType: "uint64",
      },
      {
        name: "agentCount",
        type: "uint32",
        internalType: "uint32",
      },
      {
        name: "payloadURI",
        type: "string",
        internalType: "string",
      },
    ],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "transferOwnership",
    inputs: [
      {
        name: "newOwner",
        type: "address",
        internalType: "address",
      },
    ],
    outputs: [],
    stateMutability: "nonpayable",
  },
  {
    type: "function",
    name: "verify",
    inputs: [
      {
        name: "snapshotId",
        type: "uint256",
        internalType: "uint256",
      },
      {
        name: "agentId",
        type: "uint256",
        internalType: "uint256",
      },
      {
        name: "liveness",
        type: "uint16",
        internalType: "uint16",
      },
      {
        name: "trust",
        type: "uint16",
        internalType: "uint16",
      },
      {
        name: "confidence",
        type: "uint16",
        internalType: "uint16",
      },
      {
        name: "computedAt",
        type: "uint64",
        internalType: "uint64",
      },
      {
        name: "proof",
        type: "bytes32[]",
        internalType: "bytes32[]",
      },
    ],
    outputs: [
      {
        name: "",
        type: "bool",
        internalType: "bool",
      },
    ],
    stateMutability: "view",
  },
  {
    type: "event",
    name: "OwnershipTransferStarted",
    inputs: [
      {
        name: "previousOwner",
        type: "address",
        indexed: true,
        internalType: "address",
      },
      {
        name: "newOwner",
        type: "address",
        indexed: true,
        internalType: "address",
      },
    ],
    anonymous: false,
  },
  {
    type: "event",
    name: "OwnershipTransferred",
    inputs: [
      {
        name: "previousOwner",
        type: "address",
        indexed: true,
        internalType: "address",
      },
      {
        name: "newOwner",
        type: "address",
        indexed: true,
        internalType: "address",
      },
    ],
    anonymous: false,
  },
  {
    type: "event",
    name: "PublisherSet",
    inputs: [
      {
        name: "publisher",
        type: "address",
        indexed: true,
        internalType: "address",
      },
      {
        name: "allowed",
        type: "bool",
        indexed: false,
        internalType: "bool",
      },
    ],
    anonymous: false,
  },
  {
    type: "event",
    name: "SnapshotPublished",
    inputs: [
      {
        name: "id",
        type: "uint256",
        indexed: true,
        internalType: "uint256",
      },
      {
        name: "merkleRoot",
        type: "bytes32",
        indexed: false,
        internalType: "bytes32",
      },
      {
        name: "agentCount",
        type: "uint32",
        indexed: false,
        internalType: "uint32",
      },
      {
        name: "computedAt",
        type: "uint64",
        indexed: false,
        internalType: "uint64",
      },
      {
        name: "payloadURI",
        type: "string",
        indexed: false,
        internalType: "string",
      },
    ],
    anonymous: false,
  },
  {
    type: "error",
    name: "EmptyRoot",
    inputs: [],
  },
  {
    type: "error",
    name: "NoSnapshots",
    inputs: [],
  },
  {
    type: "error",
    name: "NotPublisher",
    inputs: [],
  },
  {
    type: "error",
    name: "OwnableInvalidOwner",
    inputs: [
      {
        name: "owner",
        type: "address",
        internalType: "address",
      },
    ],
  },
  {
    type: "error",
    name: "OwnableUnauthorizedAccount",
    inputs: [
      {
        name: "account",
        type: "address",
        internalType: "address",
      },
    ],
  },
  {
    type: "error",
    name: "ScoreOutOfRange",
    inputs: [],
  },
  {
    type: "error",
    name: "UnknownSnapshot",
    inputs: [],
  },
] as const;

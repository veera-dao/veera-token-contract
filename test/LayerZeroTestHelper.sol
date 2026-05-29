// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {OApp, Origin} from "@layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";
import {OFT} from "@layerzerolabs/oapp-evm/contracts/oft/OFT.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {
    MessagingParams,
    MessagingFee,
    MessagingReceipt
} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";

contract MockEndpoint {
    uint32 public immutable eid;
    address public delegate;
    LayerZeroTestHelper public testHelper;

    constructor(uint32 _eid, address _testHelper) {
        eid = _eid;
        testHelper = LayerZeroTestHelper(_testHelper);
    }

    function setDelegate(address _delegate) external {
        delegate = _delegate;
    }

    function lzToken() external pure returns (address) {
        return address(0);
    }

    function send(MessagingParams calldata _params, address _refundAddress)
        external
        payable
        returns (MessagingReceipt memory receipt)
    {
        bytes32 guid = keccak256(abi.encodePacked(_params.dstEid, msg.sender, _params.message));
        uint64 nonce = testHelper.incrementNonce(eid, _params.dstEid);

        receipt = MessagingReceipt({guid: guid, nonce: nonce, fee: MessagingFee(msg.value, 0)});

        testHelper.schedulePacket(eid, _params.dstEid, msg.sender, _params.receiver, nonce, guid, _params.message);
    }

    function quote(
        MessagingParams calldata,
        /*_params*/
        address /*_sender*/
    )
        external
        view
        returns (MessagingFee memory fee)
    {
        return MessagingFee(100, 0); // Flat fee of 100 wei
    }
}

contract OFTMock is OFT {
    constructor(string memory _name, string memory _symbol, address _lzEndpoint, address _delegate)
        OFT(_name, _symbol, _lzEndpoint, _delegate)
        Ownable(_delegate)
    {}

    function mint(address _to, uint256 _amount) public {
        _mint(_to, _amount);
    }
}

contract LayerZeroTestHelper is Test {
    struct Packet {
        uint32 srcEid;
        uint32 dstEid;
        address sender;
        bytes32 receiver;
        uint64 nonce;
        bytes32 guid;
        bytes message;
    }

    mapping(uint32 => MockEndpoint) public endpoints;
    mapping(uint32 => mapping(uint32 => uint64)) public nonces; // srcEid => dstEid => nonce
    Packet[] public packets;

    function setUp() public virtual {}

    function setUpEndpoints(uint8 _endpointNum) public {
        for (uint32 i = 1; i <= _endpointNum; i++) {
            endpoints[i] = new MockEndpoint(i, address(this));
        }
    }

    function incrementNonce(uint32 _srcEid, uint32 _dstEid) external returns (uint64) {
        nonces[_srcEid][_dstEid]++;
        return nonces[_srcEid][_dstEid];
    }

    function schedulePacket(
        uint32 _srcEid,
        uint32 _dstEid,
        address _sender,
        bytes32 _receiver,
        uint64 _nonce,
        bytes32 _guid,
        bytes calldata _message
    ) external {
        packets.push(
            Packet({
                srcEid: _srcEid,
                dstEid: _dstEid,
                sender: _sender,
                receiver: _receiver,
                nonce: _nonce,
                guid: _guid,
                message: _message
            })
        );
    }

    function wireOApps(address[] memory ofts) public {
        uint256 size = ofts.length;
        for (uint256 i = 0; i < size; i++) {
            OApp localOApp = OApp(payable(ofts[i]));
            for (uint256 j = 0; j < size; j++) {
                if (i == j) continue;
                OApp remoteOApp = OApp(payable(ofts[j]));
                uint32 remoteEid = (remoteOApp.endpoint()).eid();
                localOApp.setPeer(remoteEid, addressToBytes32(address(remoteOApp)));
            }
        }
    }

    function verifyPackets(uint32 _dstEid, address _dstAddress) public {
        bytes32 dstAddressBytes32 = addressToBytes32(_dstAddress);

        uint256 i = 0;
        while (i < packets.length) {
            Packet memory p = packets[i];
            if (p.dstEid == _dstEid && p.receiver == dstAddressBytes32) {
                // Remove packet from array
                for (uint256 j = i; j < packets.length - 1; j++) {
                    packets[j] = packets[j + 1];
                }
                packets.pop();

                // Deliver the packet
                deliverPacket(p);
            } else {
                i++;
            }
        }
    }

    function deliverPacket(Packet memory p) internal {
        address dstEndpoint = address(endpoints[p.dstEid]);
        address targetOApp = bytes32ToAddress(p.receiver);

        Origin memory origin = Origin({srcEid: p.srcEid, sender: addressToBytes32(p.sender), nonce: p.nonce});

        vm.prank(dstEndpoint);
        OApp(payable(targetOApp)).lzReceive{gas: 2000000}(origin, p.guid, p.message, address(0), "");
    }

    function addressToBytes32(address _addr) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(_addr)));
    }

    function bytes32ToAddress(bytes32 _b) internal pure returns (address) {
        return address(uint160(uint256(_b)));
    }
}

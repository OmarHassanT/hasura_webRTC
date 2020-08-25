import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:flutter_webrtc/webrtc.dart';
import 'package:hasura_connect/hasura_connect.dart';
import 'package:videoAppFluuter/src/calling/random_string.dart';
import 'package:videoAppFluuter/src/utils/hasura.dart';

enum SignalingState {
  CallStateNew,
  CallStateRinging,
  CallStateInvite,
  CallStateConnected,
  CallStateBye,
  ConnectionOpen,
  ConnectionClosed,
  ConnectionError,
}

/*
 * callbacks for Signaling API.
 */
typedef void SignalingStateCallback(SignalingState state);
typedef void StreamStateCallback(MediaStream stream);
typedef void OtherEventCallback(dynamic event);
typedef void DataChannelMessageCallback(
    RTCDataChannel dc, RTCDataChannelMessage data);
typedef void DataChannelCallback(RTCDataChannel dc);

class Signaling {
  JsonEncoder _encoder = new JsonEncoder();
  JsonDecoder _decoder = new JsonDecoder();
  String _selfId;
  HasuraConnection _hasura;
  var _sessionId;
  var _host;
  var _port = 8086;
  var _peerConnections = new Map<String, RTCPeerConnection>();
  var _dataChannels = new Map<String, RTCDataChannel>();
  var _remoteCandidates = [];
  var _turnCredential;
  var description;
  bool offerPassed = false;
  List<dynamic> receivedData = new List<dynamic>();
  MediaStream _localStream;
  List<MediaStream> _remoteStreams;
  SignalingStateCallback onStateChange;
  StreamStateCallback onLocalStream;
  StreamStateCallback onAddRemoteStream;
  StreamStateCallback onRemoveRemoteStream;
  OtherEventCallback onPeersUpdate;
  DataChannelMessageCallback onDataChannelMessage;
  DataChannelCallback onDataChannel;
  static String url = 'http://35.224.121.33:5021/v1/graphql';

//   String updataQuerySetValidFalse = r"""
//       mutation MyMutation2($sessionId:String!) {
//   update_call_signaling(_set: {valid: false}, where: {session_id: {_eq:$sessionId}}) {
//     affected_rows
//   }
// }
//       """;

  Map<String, dynamic> _iceServers = {
    'iceServers': [
      {'url': 'stun:stun.l.google.com:19302'},
      /*
       * turn server configuration example.
      {
        'url': 'turn:123.45.67.89:3478',
        'username': 'change_to_real_user',
        'credential': 'change_to_real_secret'
      },
       */
    ]
  };

  final Map<String, dynamic> _config = {
    'mandatory': {},
    'optional': [
      {'DtlsSrtpKeyAgreement': true},
    ],
  };
  //omar
  final Map<String, dynamic> _audio_constraint = {
    'mandatory': {
      'OfferToReceiveAudio': true,
      'OfferToReceiveVideo': false,
    },
    'optional': [],
  };
  // final Map<String, dynamic> _video_constraints = {
  //   'mandatory': {
  //     'OfferToReceiveAudio': true,
  //     'OfferToReceiveVideo': true,
  //   },
  //   'optional': [],
  // };

  // final Map<String, dynamic> _dc_constraints = {
  //   'mandatory': {
  //     'OfferToReceiveAudio': false,
  //     'OfferToReceiveVideo': false,
  //   },
  //   'optional': [],
  // };

  Signaling(this._selfId);

  close() {
    if (_localStream != null) {
      _localStream.dispose();
      _localStream = null;
    }

    _peerConnections.forEach((key, pc) {
      pc.close();
    });
    //  if (_socket != null) _socket.close();
  }

  void switchCamera() {
    if (_localStream != null) {
      _localStream.getVideoTracks()[0].switchCamera();
    }
  }

  //////
  void microphoneMute(bool mute) {
    if (_localStream != null) {
      _localStream.getAudioTracks()[0].setMicrophoneMute(mute);
    }
  }

  void speakerPhone(bool enable) {
    if (_localStream != null)
      _localStream.getAudioTracks()[0].enableSpeakerphone(enable);
  }

///////
  void invite(String peer_id, String media) {
    this._sessionId = this._selfId + '-' + peer_id;

    if (this.onStateChange != null) {
      this.onStateChange(SignalingState.CallStateNew);
    }

    _createPeerConnection(peer_id, media).then((pc) {
      _peerConnections[peer_id] = pc;

      _createOffer(peer_id, pc, media);
    });
  }

  void bye(id) {
    _send('bye', {
      'session_id': this._sessionId,
      'from': this._selfId,
      'to': id,
    });
  }

  Future<void> onMessage(message) async {
    Map<String, dynamic> mapData = message;
    var data = mapData['data'];

    switch (mapData['type']) {
      case 'offer':
        {
          Map<String, dynamic> peer = new Map<String, dynamic>();
          peer["peerId"] = data['from'];
          this.onPeersUpdate(peer);

          var id = data['from'];
          var description = data['description'];
          var media = data['media'];
          var sessionId = data['session_id'];
          this._sessionId = sessionId;

          if (this.onStateChange != null) {
            this.onStateChange(SignalingState.CallStateNew);
          }
          var pc = await _createPeerConnection(id, media);
          _peerConnections[id] = pc;
          await pc.setRemoteDescription(new RTCSessionDescription(
              description['sdp'], description['type']));
          await _createAnswer(id, pc, media);
          if (this._remoteCandidates.length > 0) {
            _remoteCandidates.forEach((candidate) async {
              await pc.addCandidate(candidate);
            });
            _remoteCandidates.clear();
          }
        }
        break;
      case 'answer':
        {
          var id = data['from'];
          var description = data['description'];

          var pc = _peerConnections[id];
          if (pc != null) {
            await pc.setRemoteDescription(new RTCSessionDescription(
                description['sdp'], description['type']));
          }
        }
        break;
      case 'candidate':
        {
          print("canddddddddddddddddddddddddd");
          var id = data['from'];
          var candidateMap = data['candidate'];
          var pc = _peerConnections[id];
          RTCIceCandidate candidate = new RTCIceCandidate(
              candidateMap['candidate'],
              candidateMap['sdpMid'],
              candidateMap['sdpMLineIndex']);
          if (pc != null) {
            await pc.addCandidate(candidate);
          } else {
            _remoteCandidates.add(candidate);
          }
        }
        break;
      case 'leave':
        {
          var id = data;
          var pc = _peerConnections.remove(id);
          _dataChannels.remove(id);

          if (_localStream != null) {
            _localStream.dispose();
            _localStream = null;
          }

          if (pc != null) {
            pc.close();
          }
          this._sessionId = null;
          if (this.onStateChange != null) {
            this.onStateChange(SignalingState.CallStateBye);
          }
        }
        break;
      case 'bye':
        {
          var to = data['to'];
          var sessionId = data['session_id'];
          print('bye: ' + sessionId);

          if (_localStream != null) {
            _localStream.dispose();
            _localStream = null;
          }

          var pc = _peerConnections[to];
          if (pc != null) {
            pc.close();
            _peerConnections.remove(to);
          }

          var dc = _dataChannels[to];
          if (dc != null) {
            dc.close();
            _dataChannels.remove(to);
          }

          this._sessionId = null;
          if (this.onStateChange != null) {
            this.onStateChange(SignalingState.CallStateBye);
          }
        }
        break;
      case 'keepalive':
        {
          print('keepalive response!');
        }
        break;
      default:
        break;
    }
  }

  // List<dynamic> data_received = new List<dynamic>();
  // var receivedTypeData;

  void connect() async {
    HasuraConnect hasuraConnect = new HasuraConnect(url);

    _hasura = new HasuraConnection(_selfId, hasuraConnect);
    if (_turnCredential == null) {
      try {
        _iceServers = {
          'iceServers': [
            {
              'url': 'turn:numb.viagenie.ca',
              'credential': 'muazkh',
              'username': 'webrtc@live.com'
            },
          ]
        };
      } catch (e) {}
    }
    _hasura.onMessage = (massege) {
      print("Received massege: ");
      print(massege);
      this.onMessage(massege);
    };
    await _hasura.connect();
  }

  Future<MediaStream> createStream(media) async {
    final Map<String, dynamic> mediaConstraintsAudio = {
      'audio': true,
      'video': false
    };
    print(" 222222222222222");
    MediaStream stream = await navigator.getUserMedia(mediaConstraintsAudio);
    if (this.onLocalStream != null) {
      this.onLocalStream(stream);
    }
    print(" 33333333333333333333");

    return stream;
  }

  _createPeerConnection(id, media) async {
    print("111111111111111");
    _localStream = await createStream(media);
    print("4444444444444444");

    RTCPeerConnection pc = await createPeerConnection(_iceServers, _config);
    print("55555555555555555");

    if (media != 'data') pc.addStream(_localStream);
    print("666666666666666666");

    pc.onIceCandidate = (candidate) {
      _send('candidate', {
        'to': id,
        'from': _selfId,
        'candidate': {
          'sdpMLineIndex': candidate.sdpMlineIndex,
          'sdpMid': candidate.sdpMid,
          'candidate': candidate.candidate,
        },
        'session_id': this._sessionId,
      });
    };
    print("777777777777777777777");

    pc.onIceConnectionState = (state) {};

    pc.onAddStream = (stream) {
      if (this.onAddRemoteStream != null) this.onAddRemoteStream(stream);
      // _remoteStreams.add(stream);
    };

    pc.onRemoveStream = (stream) {
      if (this.onRemoveRemoteStream != null) this.onRemoveRemoteStream(stream);
      _remoteStreams.removeWhere((it) {
        return (it.id == stream.id);
      });
    };

    return pc;
  }

  _createOffer(String id, RTCPeerConnection pc, String media) async {
    try {
      RTCSessionDescription s = await pc.createOffer(_audio_constraint);
      pc.setLocalDescription(s);
      _send('offer', {
        'to': id,
        'from': _selfId,
        'description': {'sdp': s.sdp, 'type': s.type},
        'session_id': this._sessionId,
        'media': media,
      });
    } catch (e) {
      print(e.toString());
    }
  }

  _createAnswer(String id, RTCPeerConnection pc, media) async {
    try {
      RTCSessionDescription s = await pc.createAnswer(_audio_constraint);
      pc.setLocalDescription(s);
      _send('answer', {
        'to': id,
        'from': _selfId,
        'description': {'sdp': s.sdp, 'type': s.type},
        'session_id': this._sessionId,
        'media': media,
      });
    } catch (e) {
      print(e.toString());
    }
  }

// if (event == "bye") {
  //   var r = await hasuraConnect.mutation(updataQuerySetValidFalse,
  //       variables: {"sessionId": data["session_id"]});
  //   print("update data:");
  //   print(r);
  // }
  // List<dynamic> dataToServer = new List<dynamic>();
  _send(event, data) async {
    print("send: ");
    print(data);
    _hasura.send(event, data);
  }
}

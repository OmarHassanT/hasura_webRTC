import 'package:audioplayers/audio_cache.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'dart:core';
import 'signaling.dart';
import 'package:flutter_webrtc/webrtc.dart';
import 'random_string.dart';

class CallSample extends StatefulWidget {
  static String tag = 'call_sample';

  final String ip;

  CallSample({Key key, @required this.ip}) : super(key: key);

  @override
  _CallSampleState createState() => _CallSampleState();
}

class _CallSampleState extends State<CallSample> {
  Signaling _signaling;
  String _selfId = randomNumeric(2);
  var _peerId = "";
  RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();

  String media;
  bool _inCalling = false;
  bool isSpeaker = true;
  bool mute = false;

  _CallSampleState({Key key});

  @override
  initState() {
    super.initState();
    initRenderers();
    _connect();
  }

  initRenderers() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();
  }

  @override
  deactivate() {
    super.deactivate();
    if (_signaling != null) _signaling.close();
    _localRenderer.dispose();
    _remoteRenderer.dispose();
  }

  static AudioCache player = AudioCache();
  var playerInstance;
  void _connect() async {
    if (_signaling == null) {
      _signaling = Signaling(_selfId)..connect();

      _signaling.onStateChange = (SignalingState state) async {
        switch (state) {
          case SignalingState.CallStateNew:
            this.setState(() {
              _inCalling = true;
            });
            break;
          case SignalingState.CallStateBye:
            this.setState(() {
              _localRenderer.srcObject = null;
              _remoteRenderer.srcObject = null;
              _inCalling = false;
            });

            break;
          case SignalingState.CallStateInvite:
            playerInstance = player.loop("mp3/phone-invite.mp3");

            break;
          case SignalingState.CallStateConnected:
            break;
          case SignalingState.CallStateRinging:
            playerInstance = player.loop("mp3/messenger_ringtone.mp3");
            break;
          case SignalingState.ConnectionClosed:
            break;
          case SignalingState.ConnectionError:
            break;
          case SignalingState.ConnectionOpen:
            playerInstance.stop();

            break;
        }
      };

      _signaling.onPeersUpdate = ((peer) {
        this.setState(() {
          this._peerId = peer["peerId"];
        });
      });
      _signaling.onLocalStream = ((stream) {
        _localRenderer.srcObject = stream;
      });

      _signaling.onAddRemoteStream = ((stream) {
        _remoteRenderer.srcObject = stream;
      });

      _signaling.onRemoveRemoteStream = ((stream) {
        _remoteRenderer.srcObject = null;
      });
    }
  }

  _invitePeer(context, peerId, media) async {
    if (_signaling != null && peerId != _selfId && peerId != null) {
      _signaling.invite(peerId, media);
    }
  }

  _hangUp(peerId) {
    if (_signaling != null) {
      _signaling.close();
      this.setState(() {
        _localRenderer.srcObject = null;
        _remoteRenderer.srcObject = null;
        _inCalling = false;
      });
    }

    _signaling.bye(peerId);
  }

  _speakerEnable(bool speakerEnable) {
    _signaling.speakerPhone(speakerEnable);
  }

  _muteMic(bool mute) {
    _signaling.microphoneMute(mute);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
          title: Text('Id:$_selfId'),
          actions: <Widget>[
            IconButton(
              icon: const Icon(Icons.settings),
              onPressed: null,
              tooltip: 'setup',
            ),
          ],
        ),
        floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
        floatingActionButton: _inCalling
            ? SizedBox(
                width: 200.0,
                child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: <Widget>[
                      FloatingActionButton(
                        onPressed: () {
                          _hangUp(this._peerId);
                        },
                        tooltip: 'Hangup',
                        child: Icon(Icons.call_end),
                        backgroundColor: Colors.pink,
                      ),
                      FloatingActionButton(
                        child: Icon(mute ? Icons.mic_off : Icons.mic),
                        onPressed: () {
                          setState(() {
                            mute = !mute;
                            _muteMic(mute);
                          });
                        },
                      ),
                      FloatingActionButton(
                        child: Icon(
                            isSpeaker ? Icons.volume_up : Icons.volume_off),
                        onPressed: () {
                          setState(() {
                            isSpeaker = !isSpeaker;
                            _speakerEnable(isSpeaker);
                          });
                        },
                      ),
                    ]))
            : null,
        body: _inCalling
            ? Center(
                child: Text(
                  "$_peerId call you. running...",
                  style: TextStyle(color: Colors.green, fontSize: 40),
                  textAlign: TextAlign.center,
                ),
              )
            : Container(
                child: Center(
                  child: Column(
                    children: <Widget>[
                      TextField(
                        decoration: InputDecoration(
                            hintText: 'Enter Id of the reciver'),
                        onChanged: (peer) {
                          setState(() {
                            this._peerId = peer;
                          });
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.call),
                        onPressed: () {
                          media = 'audio';
                          _invitePeer(context, _peerId, media);
                        },
                        tooltip: 'invite',
                      ),
                    ],
                  ),
                ),
              ));
  }
}

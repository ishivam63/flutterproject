import 'dart:async';
import 'dart:io';

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_database/ui/firebase_animated_list.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chat_app/ChatMessageListItem.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:image_picker/image_picker.dart';

final googleSignIn = new GoogleSignIn();
final analytics = FirebaseAnalytics.instance;
final auth = FirebaseAuth.instance;
var currentUserEmail;
var _scaffoldContext;

class ChatScreen extends StatefulWidget {
  @override
  ChatScreenState createState() {
    return new ChatScreenState();
  }
}

class ChatScreenState extends State<ChatScreen> {
  final TextEditingController _textEditingController =
      new TextEditingController();
  bool _isComposingMessage = false;
  final reference = FirebaseDatabase.instance.ref().child('messages');

  @override
  Widget build(BuildContext context) {
    return new Scaffold(
        appBar: new AppBar(
          title: new Text("Flutter Chat App"),
          elevation:
              Theme.of(context).platform == TargetPlatform.iOS ? 0.0 : 4.0,
          actions: <Widget>[
            new IconButton(
                icon: new Icon(Icons.exit_to_app), onPressed: _signOut)
          ],
        ),
        body: new Container(
          child: new Column(
            children: <Widget>[
              new Flexible(
                child: new FirebaseAnimatedList(
                  query: reference,
                  padding: const EdgeInsets.all(8.0),
                  reverse: true,
                  sort: (a, b) {
                    final aKey = a.key;
                    final bKey = b.key;
                    if (aKey == null && bKey == null) return 0;
                    if (aKey == null) return 1;
                    if (bKey == null) return -1;
                    return bKey.compareTo(aKey);
                  },
                  //comparing timestamp of messages to check which one would appear first
                  itemBuilder: (BuildContext context, DataSnapshot messageSnapshot,
                      Animation<double> animation, int index) {
                    return new ChatMessageListItem(
                      messageSnapshot: messageSnapshot,
                      animation: animation,
                    );
                  },
                ),
              ),
              new Divider(height: 1.0),
              new Container(
                decoration:
                    new BoxDecoration(color: Theme.of(context).cardColor),
                child: _buildTextComposer(),
              ),
              new Builder(builder: (BuildContext context) {
                _scaffoldContext = context;
                return new Container(width: 0.0, height: 0.0);
              })
            ],
          ),
          decoration: Theme.of(context).platform == TargetPlatform.iOS
              ? new BoxDecoration(
                  border: new Border(
                      top: new BorderSide(
                  color: Colors.grey[200] ?? Colors.grey,
                )))
              : null,
        ));
  }

  CupertinoButton getIOSSendButton() {
    return new CupertinoButton(
      child: new Text("Send"),
      onPressed: _isComposingMessage
          ? () => _textMessageSubmitted(_textEditingController.text)
          : null,
    );
  }

  IconButton getDefaultSendButton() {
    return new IconButton(
      icon: new Icon(Icons.send),
      onPressed: _isComposingMessage
          ? () => _textMessageSubmitted(_textEditingController.text)
          : null,
    );
  }

  Widget _buildTextComposer() {
    return new IconTheme(
        data: new IconThemeData(
          color: _isComposingMessage
              ? Theme.of(context).colorScheme.secondary
              : Theme.of(context).disabledColor,
        ),
        child: new Container(
          margin: const EdgeInsets.symmetric(horizontal: 8.0),
          child: new Row(
            children: <Widget>[
              new Container(
                margin: new EdgeInsets.symmetric(horizontal: 4.0),
                child: new IconButton(
                    icon: new Icon(
                      Icons.photo_camera,
                      color: Theme.of(context).colorScheme.secondary,
                    ),
                    onPressed: () async {
                      await _ensureLoggedIn();
                      final ImagePicker picker = ImagePicker();
                      final XFile? pickedFile = await picker.pickImage(source: ImageSource.camera);
                      if (pickedFile != null) {
                        File imageFile = File(pickedFile.path);
                        int timestamp = DateTime.now().millisecondsSinceEpoch;
                        final storageRef = FirebaseStorage.instance
                            .ref()
                            .child("img_$timestamp.jpg");
                        final uploadTask = storageRef.putFile(imageFile);
                        final TaskSnapshot snapshot = await uploadTask;
                        final String downloadUrl = await snapshot.ref.getDownloadURL();
                        _sendMessage(
                            messageText: '', imageUrl: downloadUrl);
                      }
                    }),
              ),
              new Flexible(
                child: new TextField(
                  controller: _textEditingController,
                  onChanged: (String messageText) {
                    setState(() {
                      _isComposingMessage = messageText.length > 0;
                    });
                  },
                  onSubmitted: _textMessageSubmitted,
                  decoration:
                      new InputDecoration.collapsed(hintText: "Send a message"),
                ),
              ),
              new Container(
                margin: const EdgeInsets.symmetric(horizontal: 4.0),
                child: Theme.of(context).platform == TargetPlatform.iOS
                    ? getIOSSendButton()
                    : getDefaultSendButton(),
              ),
            ],
          ),
        ));
  }

  Future<void> _textMessageSubmitted(String text) async {
    _textEditingController.clear();

    setState(() {
      _isComposingMessage = false;
    });

    await _ensureLoggedIn();
    _sendMessage(messageText: text, imageUrl: '');
  }

  void _sendMessage({required String messageText, required String imageUrl}) {
    reference.push().set({
      'text': messageText,
      'email': googleSignIn.currentUser?.email ?? '',
      'imageUrl': imageUrl,
      'senderName': googleSignIn.currentUser?.displayName ?? '',
      'senderPhotoUrl': googleSignIn.currentUser?.photoUrl ?? '',
    });

    analytics.logEvent(name: 'send_message');
  }

  Future<void> _ensureLoggedIn() async {
    if (googleSignIn.currentUser == null) {
      await googleSignIn.signIn();
    }

    currentUserEmail = googleSignIn.currentUser?.email ?? '';

    final user = auth.currentUser;
    if (user == null) {
      final GoogleSignInAuthentication? credentials =
          await googleSignIn.currentUser?.authentication;
      if (credentials != null) {
        final AuthCredential authCredential = GoogleAuthProvider.credential(
          idToken: credentials.idToken, accessToken: credentials.accessToken);
        await auth.signInWithCredential(authCredential);
      }
    }
  }

  Future<void> _signOut() async {
    await auth.signOut();
    await googleSignIn.signOut();
    ScaffoldMessenger.of(_scaffoldContext)
        .showSnackBar(SnackBar(content: Text('User logged out')));
  }
}
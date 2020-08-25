import 'package:hasura_connect/hasura_connect.dart';

typedef void OnMessageCallback(Map<String, dynamic> msg);
typedef void OnCloseCallback(int code, String reason);
typedef void OnOpenCallback();

class HasuraConnection {
  String _urlSelfId;
  OnOpenCallback onOpen;
  OnMessageCallback onMessage;
  OnCloseCallback onClose;
  HasuraConnection(this._urlSelfId, this.hasuraConnect);
  HasuraConnect hasuraConnect;
  List<int> ids = new List<int>();
  bool answerPass = false;
  List<dynamic> dataa = new List<dynamic>();
  int order = 0;

  String sendData = r"""
mutation MyMutation($reciverID:String!,$request:jsonb!,$sessionId:String!,$order:Int!) {
  insert_call_signaling(objects: {User_id: $reciverID, data:$request,session_id:$sessionId,order:$order }) {
    affected_rows
  }
}
""";

  String receiveData = r"""
subscription MySubscription($_selfId: String!) {
  call_signaling(where: {User_id: {_eq: $_selfId}, valid: {_eq: true}}, order_by: {order: asc}) {
    data
    id
    order
  }
}
""";
  connect() async {
    try {
      Snapshot snapshot = hasuraConnect
          .subscription(receiveData, variables: {"_selfId": _urlSelfId});
      snapshot.listen((data) {
        dataa = data["data"]["call_signaling"];

        if (dataa.length > 0) {
          //for "offer" or "answer"
          if (!ids.contains(dataa[0]["id"])) {
            ids.add(dataa[0]["id"]);
            this?.onMessage(dataa[0]["data"]);
          }
          //for "bye"
          if (dataa[dataa.length - 1]["data"]["type"] == "bye") {
            ids.add(dataa[dataa.length - 1]["id"]);
            this?.onMessage(dataa[dataa.length - 1]["data"]);
          }
          //answer=>get candidates with answer if the event ="answer".
          if (dataa[0]["data"]["type"] == "answer") {
            for (int i = 1; i < dataa.length; i++) {
              if (!ids.contains(dataa[i]["id"])) {
                this?.onMessage(dataa[i]["data"]);
                ids.add(dataa[i]["id"]);
              }
            }
          }
        }
      });
    } catch (e) {
      print("Error: " + e);
    }
  }

  send(event, data) async {
    Map<String, dynamic> request = new Map();
    request["type"] = event;
    request["data"] = data;
    var reciverID = data["to"];

    var r = await hasuraConnect.mutation(sendData, variables: {
      "reciverID": reciverID,
      "request": request,
      "sessionId": data["session_id"],
      "order": order++
    });

    // after send answer and it's candidates,the receiver will receive the offer candidates.
    for (int i = 1; i < dataa.length; i++) {
      if (!ids.contains(dataa[i]["id"])) {
        ids.add(dataa[i]["id"]);
        this?.onMessage(dataa[i]["data"]);
      }
    }
  }
}

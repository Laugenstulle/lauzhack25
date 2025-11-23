import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:crypto/crypto.dart';
import 'dart:math';
import 'dart:convert';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:flutter/material.dart';


void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) => MyAppState(),
      child: MaterialApp(
        title: 'SBB Anonymous Ticket',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.red),
        ),
        debugShowCheckedModeBanner: false,
        home: MyHomePage(),
      ),
    );
  }
}



class MyAppState extends ChangeNotifier {

  var tickets = <Ticket>{ Ticket(
      ticketId: 'ab1f9a7df661cc7fbcc354924e3a710e717d91805f443cd2eeec0029c36ace8d',
      validFrom: DateTime.now(),
      validUntil: DateTime.now(),
      start: 'KIT',
      destination: 'EPFL',
      price: 20,
      securityFactorMethod: SecurityFactorMethod.TokenCard,
      nonce: '0',
  )};

  Future<void> generateTicket(
      String securityFactor,
      String start,
      String destination,
      DateTime validFrom,
      DateTime validUntil,
      String ticketType,
      String validatingMethod,
      ) async {
    var nonce = Random.secure().toString();
    var bytes = utf8.encode(securityFactor + nonce);
    var ticketId = sha256.convert(bytes).toString();
    Ticket ticket = await callTicketGenerationServer(
      start,
      destination,
      validFrom,
      validUntil,
      ticketType,
      validatingMethod,
      ticketId,
      nonce,
    );
    tickets.add(ticket);
    notifyListeners();
  }


}

Future<Ticket> callTicketGenerationServer(
    String start,
    String destination,
    DateTime validFrom,
    DateTime validUntil,
    String ticketType,
    String validatingMethod,
    String ticketId,
    String nonce) async {
  
  var json = await createTicket(
    start,
    destination,
    validFrom.millisecondsSinceEpoch,
    validUntil.millisecondsSinceEpoch,
    ticketType,
    validatingMethod,
    ticketId,
  );

  var ticket = Ticket.fromJson(jsonDecode(json.body) as Map<String, dynamic>, ticketId);
  ticket.nonce = nonce;
  ticket.ticketId = ticketId;
  return ticket;
}

Future<http.Response> validateTicket(
    String ticketId,
    String location
    ) async {
  return await http.post(
    Uri.parse('http://127.0.0.1:8001/tickets/$ticketId'),
    headers: <String, String>{
      'Content-Type': 'application/json; charset=UTF-8',
    },
    body: jsonEncode(<String, String>{
      "location": location
    }),
  );
}

class ValidationResponse {
  final bool isSuspicious;

  ValidationResponse({
    required this.isSuspicious,
  });

  factory ValidationResponse.fromJson(Map<String, dynamic> json) {
    return ValidationResponse(
        isSuspicious: json["suspicious"] == "true"
    );
  }

  TicketValidity toTicketValidity() {
    if (isSuspicious) {
      return TicketValidity.CheckIdentity;
    } else {
    return TicketValidity.Ok;
    }
  }
}

TicketValidity callTicketValidationServer(String ticketId, String location) {
  var json = validateTicket(ticketId, location);

  return ValidationResponse.fromJson(json as Map<String, dynamic>).toTicketValidity();

}

class Ticket {
  // Data fields
  late final String ticketId;
  final DateTime validFrom;
  final DateTime validUntil;
  final String start;
  final String destination;
  final int price;
  final SecurityFactorMethod securityFactorMethod;
  late final String nonce;


  // Constructor
  Ticket({
    required this.ticketId,
    required this.validFrom,
    required this.validUntil,
    required this.start,
    required this.destination,
    required this.price,
    required this.securityFactorMethod,
    required this.nonce,
  });

  factory Ticket.fromJson(Map<String, dynamic> json, String ticketId) {
    return Ticket(
          ticketId: ticketId,
          validFrom:  DateTime.fromMillisecondsSinceEpoch(int.parse(json["payload"]["from_datetime"] ?? "0")),
          validUntil:  DateTime.fromMillisecondsSinceEpoch(int.parse(json["payload"]["to_datetime"] ?? "0")),
          start:  json["payload"]["from_station"] ?? "0",
          destination:  json["payload"]["to_station"] ?? "0",
          price:  json["payload"]["price"] ?? "0",
          securityFactorMethod: SecurityFactorMethod.IDNumber,
          nonce: "0"
    );
  }

   Ticket fromQrCodeData(String data) {
     return Ticket(
         ticketId: data.substring(0, 32),
         validFrom: DateTime.parse(data.substring(32, 58)),
         validUntil: DateTime.parse(data.substring(58, 84)),
         start: data.substring(84, 87),
         destination: data.substring(87, 91),
         price: 0,
         securityFactorMethod: SecurityFactorMethod.IDNumber,
         nonce: '');
  }

  @override
  String toString() {
    final DateFormat formatter = DateFormat('dd.MM.yyyy');
    return "${formatter.format(validFrom)} - ${formatter.format(validUntil)}" +
        "\n$start to $destination";
  }

  String toData() {
    return "$ticketId$validFrom$validUntil$start$destination";
  }
}

Future<http.Response> createTicket(
    String start,
    String destination,
    int validFromMilliseconds,
    int validUntilMilliseconds,
    String ticketType,
    String validatingMethod,
    String ticketId,
    ) {
  return http.put(
    Uri.parse('http://127.0.0.1:8000/buy-ticket'),
    headers: <String, String>{
      'Content-Type': 'application/json; charset=UTF-8',
    },
    body: jsonEncode(<String, String>{
      "from_station": start,
      "to_station": destination,
      "from_datetime": "$validFromMilliseconds",
      "to_datetime": "$validUntilMilliseconds",
      "ticket_type": ticketType,
      "validating_methode": validatingMethod,
      "user_provided_id": ticketId
    }),
  );
}

class MyHomePage extends StatefulWidget {
  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {

  var selectedIndex = 0;

  @override
  Widget build(BuildContext context) {

    Widget page;
    switch (selectedIndex) {
      case 0:
        page = TicketGenerator();
        break;
      case 1:
        page = TicketViewer();
        break;
      case 2:
        page = TicketChecker();
        break;
      case 3:
        page = QrReader();
        break;
      default:
        throw UnimplementedError('no widget for $selectedIndex');
    }


    return LayoutBuilder(
        builder: (context, constraints) {
          return Scaffold(
            body: Row(
              children: [
                SafeArea(
                  child: NavigationRail(
                    extended: constraints.maxWidth >= 600,
                    destinations: [
                      NavigationRailDestination(
                        icon: Icon(Icons.train),
                        label: Text('Generate ticket'),
                      ),
                      NavigationRailDestination(
                        icon: Icon(Icons.qr_code),
                        label: Text('See Ticket'),
                      ),
                      NavigationRailDestination(
                        icon: Icon(Icons.check_circle_outline),
                        label: Text('Validate ticket'),
                      ),
                      NavigationRailDestination(
                        icon: Icon(Icons.qr_code_scanner),
                        label: Text('Scan ticket'),
                      ),
                    ],
                    selectedIndex: selectedIndex,
                    onDestinationSelected: (value) {
                      setState(() {
                        selectedIndex = value;
                      });
                    },
                  ),
                ),
                Expanded(
                  child: Container(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    child: page,
                  ),
                ),
              ],
            ),
          );
        }
    );
  }
}

class TicketGenerator extends StatefulWidget {
  @override
  State<TicketGenerator> createState() => _TicketGeneratorState();
}

class _TicketGeneratorState extends State<TicketGenerator> {
  SecurityFactorMethod _selectedSecurityMethod = SecurityFactorMethod.TokenCard;
  String _selectedStart = "KIT";
  String _selectedDestination = "EPFL";
  List<String> stations = ['KIT', 'EPFL', 'Bern', 'Zürich', 'Olten', 'Interlaken West'];



  @override
  Widget build(BuildContext context) {
    var appState = context.watch<MyAppState>();
    var now = DateTime.now();
    var inThreeMonth = DateTime(now.year, now.month, now.day + 1);
    final securityFactorController = TextEditingController();

     return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Center(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  DropdownButton<String>(
                    hint: Text('Select a start station'),
                    value: _selectedStart,
                    onChanged: (String? newValue) {
                      setState (() {
                        _selectedStart = newValue ?? "KIT";
                      });
                    },
                    items: stations.map<DropdownMenuItem<String>>((String type) {
                      return DropdownMenuItem<String>(
                        value: type,
                        child: Text(type), // Convert enum to string
                      );
                    }).toList(),
                  ),
                  SizedBox(width: 5,),
                  Icon(Icons.keyboard_double_arrow_right_sharp),
                  SizedBox(width: 5,),
                  DropdownButton<String>(
                    hint: Text('Select a destination'),
                    value: _selectedDestination,
                    onChanged: (String? newValue) {
                      setState (() {
                        _selectedDestination = newValue ?? "EPFL";
                      });
                    },
                    items: stations.map<DropdownMenuItem<String>>((String type) {
                      return DropdownMenuItem<String>(
                        value: type,
                        child: Text(type), // Convert enum to string
                      );
                    }).toList(),
                  ),
            ],
            ),
          ),
          SizedBox(height: 20.0,),

          Row(
            children: [
              SizedBox(width: 10,),
              DropdownButton<SecurityFactorMethod>(
                hint: Text('Select a Ticket Type'),
                value: _selectedSecurityMethod,
                onChanged: (SecurityFactorMethod? newValue) {
                  setState (() {
                    if (newValue != null) {
                      _selectedSecurityMethod = newValue;
                    }

                  });
                },
                items: SecurityFactorMethod.values.map<DropdownMenuItem<SecurityFactorMethod>>((SecurityFactorMethod type) {
                  return DropdownMenuItem<SecurityFactorMethod>(
                    value: type,
                    child: Text(type.toString().split('.').last.toUpperCase()), // Convert enum to string
                  );
                }).toList(),
              ),
              SizedBox(width: 10,),
              if (_selectedSecurityMethod != null)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: TextField(
                      controller: securityFactorController,
                      decoration: InputDecoration(
                        labelText: 'Enter your ${securityMethodToString(_selectedSecurityMethod!)}',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          SizedBox(height: 10),
          ElevatedButton(
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) {
                  appState.generateTicket(
                      securityFactorController.text,
                      _selectedStart,
                      _selectedDestination,
                      now,
                      inThreeMonth,
                      'dayticket',
                      _selectedSecurityMethod.toString(),
                  );
                  return AlertDialog(
                    content: Text('ticket generated!'),
                  );
                },
              );
            },
            child: Text('generate ticket'),
          ),
        ],
      ),
    );
  }
}


class TicketViewer extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    var appState = context.watch<MyAppState>();

    if (appState.tickets.isEmpty) {
      return Center(
        child: Text('No tickets yet.'),
      );
    }

    return ListView(
      children: [
        Padding(
          padding: const EdgeInsets.all(20),
          child: Text('You have '
              '${appState.tickets.length} tickets:'),
        ),
        for (var ticket in appState.tickets)
          BigCard(ticket: ticket)
      ],
    );
  }
}




class TicketChecker extends StatefulWidget {
  @override
  _TicketChecker createState() => _TicketChecker();
}

class _TicketChecker extends State<TicketChecker> {
  Ticket? selectedTicket;
  TicketValidity _ticketValidity = TicketValidity.Unkonwn;
  String statusText = "";
  var controller = TextEditingController();


  @override
  Widget build(BuildContext context) {
    var appState = context.watch<MyAppState>();
    var tickets = appState.tickets;
    var locationController = TextEditingController();

    if (appState.tickets.isEmpty) {
      return Center(
        child: Text('No tickets to check!'),
      );
    }

    return Scaffold(
      body: Container(
        color: Theme.of(context).colorScheme.primaryContainer,
        child: Column(
          children: [
            SizedBox(height: 50,),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  Text('Select a Ticket to validate'),
                  DropdownButton<Ticket>(
                    hint: Text('Select a Ticket'),
                    value: selectedTicket,
                    onChanged: (Ticket? newValue) {
                      setState(() {
                        selectedTicket = newValue;
                      });
                    },
                    items: tickets.map<DropdownMenuItem<Ticket>>((Ticket ticket) {
                      return DropdownMenuItem<Ticket>(
                        value: ticket,
                        child: Text('${ticket.start} -> ${ticket.destination}'),
                      );
                    }).toList(),
                  ),
                  SizedBox(height: 20),
                  if (selectedTicket != null) BigCard(ticket: selectedTicket!,),
                  SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: TextField(
                            controller: locationController,
                            decoration: InputDecoration(
                              labelText: 'location',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                      ),
                      ElevatedButton(
                        onPressed: () {
                          setState(() {
                            //_ticketValidity = callTicketValidationServer(selectedTicket!.ticketId, locationController.text);
                            _ticketValidity = TicketValidity.CheckIdentity;
                            locationController.clear();
                          });
                          },
                        child: Text('check ticket'),
                      ),
                    ],
                  ),
                  SizedBox(height: 20,),
                  if (selectedTicket != null)
                    validityToCard(_ticketValidity, context, selectedTicket!),
                  if (_ticketValidity ==  TicketValidity.CheckIdentity && (selectedTicket != null) && selectedTicket!.securityFactorMethod != null)
                    Row(
                      children: [
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: TextField(
                                controller: controller,
                                decoration: InputDecoration(
                                    labelText: 'Enter clients ${securityMethodToString(selectedTicket!.securityFactorMethod)}',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ),
                          ),
                        ElevatedButton(
                            onPressed: () {
                              setState(() {

                                if (checkIdentity(controller.text, selectedTicket!)) {
                                  _ticketValidity = TicketValidity.Ok;
                                  return;
                                }
                                _ticketValidity = TicketValidity.Invalid;
                              });
                            },
                            child: Text('Check Identity'))
                      ],
                    ),


              ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}



class BigCard extends StatelessWidget {
  const BigCard({
    super.key,
    required this.ticket,
  });

  final Ticket ticket;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.bodyMedium!.copyWith(
      color:  theme.colorScheme.onPrimary,
    );

    return Card (
      color: theme.colorScheme.primary,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(
                child: SizedBox(
                  height: 200,
                  width: 200,
                  child: QrImageView(
                    data: ticket.toData(),
                    padding: EdgeInsets.all(5.0),
                    version: QrVersions.auto,
                    backgroundColor: Colors.white,
                  ),
                ),
            ),
            SizedBox(width: 10,),
            Text(
              ticket.toString(),
              style: style,
            ),
          ],
        ),
      ),
    );
  }
}

enum TicketValidity {
  Ok,
  CheckIdentity,
  Invalid,
  Unkonwn,
}

bool checkIdentity(String securityFactor, Ticket shownTicket) {
  var bytes = utf8.encode(securityFactor + shownTicket.nonce);
  var ticketId = sha256.convert(bytes).toString();

  return ticketId == shownTicket.ticketId;
}

SizedBox validityToCard(TicketValidity validity, BuildContext context, Ticket controlledTicket) {
  switch (validity) {

    case TicketValidity.Ok:
      return SizedBox(
        height: 80,
        child: Card(
          color: Colors.green,
          child: Center(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.check),
                SizedBox(width: 5.0,),
                Text('Validation successful'),
              ],
            ),
          ),
        ),
      );
    case TicketValidity.CheckIdentity:
      return SizedBox(
        height: 80,
        child: Card(
          color: Colors.orange,
          child: Center(
            child:
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.perm_identity),
                    SizedBox(width: 5.0,),
                    Text('Check Identity of client!'),
                  ],
                ),

          ),
        ),
      );
    case TicketValidity.Invalid:
      return SizedBox(
        height: 80,
        child: Card(
          color: Colors.red,
          child: Center(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.warning),
                SizedBox(width: 5.0,),
                Text('Ticket invalid!'),
              ],
            ),
          ),
        ),
      );
    case TicketValidity.Unkonwn:
      return SizedBox(
      );
  }
}

String securityMethodToString(SecurityFactorMethod secMethod) {
  switch (secMethod) {

    case SecurityFactorMethod.TokenCard:
      return "SBB anonymouse Token card";
    case SecurityFactorMethod.IDNumber:
      return "ID number";
  }
}



enum SecurityFactorMethod {
  TokenCard,
  IDNumber,
}

class QrReader extends StatefulWidget {
  const QrReader({super.key});

  @override
  State<QrReader> createState() => _QrReader();
}

class _QrReader extends State<QrReader> {
  String? _result;

  void setResult(String result) {
    setState(() => _result = result);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_result ?? 'No result'),
            ElevatedButton(
              child: const Text('Scan QR code'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => QrCodeScanner(setResult: setResult),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}


class QrCodeScanner extends StatelessWidget {
  QrCodeScanner({required this.setResult,super.key});

  final MobileScannerController controller = MobileScannerController();
  final Function setResult;

  @override
  Widget build(BuildContext context) {
    return MobileScanner(
      controller: controller,
      onDetect: (BarcodeCapture capture) async {
        final List<Barcode> barcodes = capture.barcodes;

        final barcode = barcodes.first;

        if (barcode.rawValue != null) {
          setResult(barcode.rawValue);

          await controller
              .stop()
              .then((value) => controller.dispose())
              .then((value) => Navigator.of(context).pop());
        }
      },
    );
  }
}
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:crypto/crypto.dart';
import 'dart:math';
import 'dart:convert';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:mobile_scanner/mobile_scanner.dart';

const String baseUrl = 'http://127.0.0.1:8000';

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
          useMaterial3: true,
        ),
        debugShowCheckedModeBanner: false,
        home: MyHomePage(),
      ),
    );
  }
}

class MyAppState extends ChangeNotifier {
  var tickets = <Ticket>[];
  Map<String, List<dynamic>> availableRoutes = {};
  bool isLoadingRoutes = true;

  MyAppState() {
    _fetchRoutesFromBackend();
  }

  Future<void> _fetchRoutesFromBackend() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/routes'));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        availableRoutes = Map<String, List<dynamic>>.from(data['routes']);
      } else {
        print('Failed to load routes: ${response.statusCode}');
      }
    } catch (e) {
      print('Error fetching routes: $e');
    } finally {
      isLoadingRoutes = false;
      notifyListeners();
    }
  }

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
    var ticketId = sha256.convert(bytes).toString().substring(0, 32);

    try {
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
    } catch (e) {
      print("Error generating ticket: $e");
    }
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

  var response = await createTicket(
    start,
    destination,
    validFrom.millisecondsSinceEpoch ~/ 1000,
    validUntil.millisecondsSinceEpoch ~/ 1000,
    ticketType,
    validatingMethod,
    ticketId,
  );

  if (response.statusCode != 200) {
    throw Exception('Failed to create ticket: ${response.body}');
  }

  var ticket = Ticket.fromJson(jsonDecode(response.body) as Map<String, dynamic>, ticketId);
  ticket.nonce = nonce;
  ticket.ticketId = ticketId;
  return ticket;
}

Future<http.Response> createTicket(
    String start,
    String destination,
    int validFromSeconds,
    int validUntilSeconds,
    String ticketType,
    String validatingMethod,
    String ticketId,
    ) {
  return http.put(
    Uri.parse('$baseUrl/buy-ticket'),
    headers: <String, String>{
      'Content-Type': 'application/json; charset=UTF-8',
    },
    body: jsonEncode(<String, dynamic>{
      "from_station": start,
      "to_station": destination,
      "from_datetime": validFromSeconds,
      "to_datetime": validUntilSeconds,
      "ticket_type": ticketType,
      "validating_methode": validatingMethod,
      "user_provided_id": ticketId
    }),
  );
}

Future<http.Response> validateTicket(String ticketId, String location) async {
  return await http.put(
    Uri.parse('$baseUrl/register/$ticketId'),
    headers: <String, String>{
      'Content-Type': 'application/json; charset=UTF-8',
    },
    body: jsonEncode(<String, String>{
      "location": location
    }),
  );
}

Future<TicketValidity> callTicketValidationServer(String ticketId, String location) async {
  try {
    var response = await validateTicket(ticketId, location);
    if (response.statusCode == 200) {
      return fromJsonToValitity(jsonDecode(response.body) as Map<String, dynamic>);
    }
    return TicketValidity.Invalid;
  } catch (e) {
    print(e);
    return TicketValidity.Unkonwn;
  }
}

TicketValidity fromJsonToValitity(Map<String, dynamic> json) {
  var isSuspicious = json["suspicious"].toString().toLowerCase() == "true";
  if (isSuspicious) {
    return TicketValidity.CheckIdentity;
  }
  return TicketValidity.Ok;
}


class Ticket {
  String ticketId;
  final DateTime validFrom;
  final DateTime validUntil;
  final String start;
  final String destination;
  final int price;
  final SecurityFactorMethod securityFactorMethod;
  String nonce;
  final String signature;

  Ticket({
    required this.ticketId,
    required this.validFrom,
    required this.validUntil,
    required this.start,
    required this.destination,
    required this.price,
    required this.securityFactorMethod,
    required this.nonce,
    required this.signature,
  });

  factory Ticket.fromJson(Map<String, dynamic> json, String ticketId) {
    var payload = json["payload"];
    var fromTime = DateTime.fromMillisecondsSinceEpoch((payload["from_datetime"] * 1000).toInt());
    var toTime = DateTime.fromMillisecondsSinceEpoch((payload["to_datetime"] * 1000).toInt());

    return Ticket(
      ticketId: ticketId,
      validFrom: fromTime,
      validUntil: toTime,
      start: payload["from_station"] ?? "Unknown",
      destination: payload["to_station"] ?? "Unknown",
      price: payload["price"] ?? 0,
      securityFactorMethod: SecurityFactorMethod.IDNumber,
      nonce: "0",
      signature: json["sign"],
    );
  }

  String toData() {
    return "${ticketId}_${validFrom}_${validUntil}_${start}_${destination}_${price}_${nonce}_${signature}";
  }

  @override
  String toString() {
    final DateFormat formatter = DateFormat('dd.MM.yyyy HH:mm');
    return "${formatter.format(validFrom)} - ${formatter.format(validUntil)}\n$start to $destination";
  }
}

enum TicketValidity { Ok, CheckIdentity, Invalid, Unkonwn }
enum SecurityFactorMethod { TokenCard, IDNumber }

String securityMethodToString(SecurityFactorMethod secMethod) {
  switch (secMethod) {
    case SecurityFactorMethod.TokenCard: return "SBB anonymous Token card";
    case SecurityFactorMethod.IDNumber: return "ID number";
  }
}

bool checkIdentity(String securityFactor, Ticket shownTicket) {
  var bytes = utf8.encode(securityFactor + shownTicket.nonce);
  var ticketId = sha256.convert(bytes).toString().substring(0, 32);
  return ticketId == shownTicket.ticketId;
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
      case 0: page = TicketGenerator(); break;
      case 1: page = TicketViewer(); break;
      case 2: page = TicketChecker(); break;
      case 3: page = QrReader(); break;
      default: throw UnimplementedError('no widget for $selectedIndex');
    }

    return LayoutBuilder(
        builder: (context, constraints) {
          return Scaffold(
            body: Row(
              children: [
                SafeArea(
                  child: NavigationRail(
                    extended: constraints.maxWidth >= 600,
                    destinations: const [
                      NavigationRailDestination(icon: Icon(Icons.train), label: Text('Generate')),
                      NavigationRailDestination(icon: Icon(Icons.qr_code), label: Text('My Tickets')),
                      NavigationRailDestination(icon: Icon(Icons.check_circle_outline), label: Text('Validate')),
                      NavigationRailDestination(icon: Icon(Icons.qr_code_scanner), label: Text('Scan')),
                    ],
                    selectedIndex: selectedIndex,
                    onDestinationSelected: (value) => setState(() => selectedIndex = value),
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
  String? _selectedStart;
  String? _selectedDestination;
  SecurityFactorMethod? _selectedSecurityMethod;
  final TextEditingController securityFactorController = TextEditingController();

  final DateTime now = DateTime.now();
  late DateTime inThreeMonth;

  @override
  void initState() {
    super.initState();
    inThreeMonth = DateTime(now.year, now.month + 3, now.day);
  }

  @override
  Widget build(BuildContext context) {
    var appState = context.watch<MyAppState>();

    if (appState.isLoadingRoutes) {
      return Center(child: CircularProgressIndicator());
    }

    if (appState.availableRoutes.isEmpty) {
      return Center(child: Text("No routes available. Check server connection."));
    }

    List<String> destinations = [];
    if (_selectedStart != null && appState.availableRoutes.containsKey(_selectedStart)) {
      destinations = List<String>.from(appState.availableRoutes[_selectedStart]!);
    }

    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text("Buy Ticket", style: Theme.of(context).textTheme.headlineSmall),
          SizedBox(height: 20),

          DropdownButtonFormField<String>(
            decoration: InputDecoration(border: OutlineInputBorder(), labelText: "Start Station"),
            value: _selectedStart,
            items: appState.availableRoutes.keys.map((String station) {
              return DropdownMenuItem(value: station, child: Text(station));
            }).toList(),
            onChanged: (val) {
              setState(() {
                _selectedStart = val;
                _selectedDestination = null;
              });
            },
          ),
          SizedBox(height: 10),

          DropdownButtonFormField<String>(
            decoration: InputDecoration(border: OutlineInputBorder(), labelText: "Destination"),
            value: _selectedDestination,
            items: destinations.map((String station) {
              return DropdownMenuItem(value: station, child: Text(station));
            }).toList(),
            onChanged: _selectedStart == null ? null : (val) {
              setState(() => _selectedDestination = val);
            },
          ),
          SizedBox(height: 10),

          Row(
            children: [
              Expanded(
                flex: 2,
                child: DropdownButtonFormField<SecurityFactorMethod>(
                  decoration: InputDecoration(border: OutlineInputBorder(), labelText: "ID Type"),
                  value: _selectedSecurityMethod,
                  items: SecurityFactorMethod.values.map((type) {
                    return DropdownMenuItem(
                      value: type,
                      child: Text(type.toString().split('.').last),
                    );
                  }).toList(),
                  onChanged: (val) => setState(() => _selectedSecurityMethod = val),
                ),
              ),
              SizedBox(width: 10),
              if (_selectedSecurityMethod != null)
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: securityFactorController,
                    decoration: InputDecoration(
                      labelText: 'Enter ${securityMethodToString(_selectedSecurityMethod!)}',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
            ],
          ),
          SizedBox(height: 20),

          ElevatedButton.icon(
            icon: Icon(Icons.confirmation_number),
            label: Text('Generate Ticket'),
            onPressed: (_selectedStart == null || _selectedDestination == null || _selectedSecurityMethod == null)
                ? null
                : () async {
              await appState.generateTicket(
                securityFactorController.text,
                _selectedStart!,
                _selectedDestination!,
                DateTime.now().add(Duration(minutes: 5)),
                DateTime.now().add(Duration(hours: 4)),
                'dayticket',
                _selectedSecurityMethod.toString(),
              );

              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Ticket Generated! Check "My Tickets" tab.'))
                );
              }
            },
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
      return Center(child: Text('No tickets yet.'));
    }

    return ListView(
      children: [
        Padding(
          padding: const EdgeInsets.all(20),
          child: Text('You have ${appState.tickets.length} tickets:'),
        ),
        for (var ticket in appState.tickets) BigCard(ticket: ticket)
      ],
    );
  }
}

class TicketChecker extends StatefulWidget {
  @override
  State<TicketChecker> createState() => _TicketCheckerState();
}

class _TicketCheckerState extends State<TicketChecker> {
  Ticket? selectedTicket;
  TicketValidity _ticketValidity = TicketValidity.Unkonwn;
  final controller = TextEditingController();
  final locationController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    var appState = context.watch<MyAppState>();
    var tickets = appState.tickets;

    if (tickets.isEmpty) {
      return Center(child: Text('No tickets available locally to check!'));
    }

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            DropdownButton<Ticket>(
              isExpanded: true,
              hint: Text('Select a Ticket to simulate scan'),
              value: selectedTicket,
              onChanged: (Ticket? newValue) {
                setState(() {
                  selectedTicket = newValue;
                  _ticketValidity = TicketValidity.Unkonwn;
                });
              },
              items: tickets.map((Ticket ticket) {
                return DropdownMenuItem(
                  value: ticket,
                  child: Text('${ticket.start} -> ${ticket.destination} (${ticket.ticketId.substring(0,8)}...)'),
                );
              }).toList(),
            ),
            SizedBox(height: 20),
            if (selectedTicket != null) BigCard(ticket: selectedTicket!),
            SizedBox(height: 20),

            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: locationController,
                    decoration: InputDecoration(
                      labelText: 'Current Location',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                SizedBox(width: 10),
                ElevatedButton(
                  onPressed: () async {
                    if (selectedTicket == null) return;
                    var location = locationController.text;
                    if (selectedTicket!.start != location&& selectedTicket!.destination != location) {
                      _ticketValidity = TicketValidity.Invalid;
                      return;
                    }
                    var val = await callTicketValidationServer(selectedTicket!.ticketId, locationController.text);
                    setState(() {
                      _ticketValidity = val;
                    });
                  },
                  child: Text('Validate'),
                ),
              ],
            ),
            SizedBox(height: 20),

            if (_ticketValidity != TicketValidity.Unkonwn)
              validityToCard(_ticketValidity),

            if (_ticketValidity == TicketValidity.CheckIdentity && selectedTicket != null)
              Padding(
                padding: const EdgeInsets.only(top: 20),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: controller,
                        decoration: InputDecoration(
                          labelText: 'Verify ${securityMethodToString(selectedTicket!.securityFactorMethod)}',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    SizedBox(width: 10),
                    ElevatedButton(
                      onPressed: () {
                        setState(() {
                          if (checkIdentity(controller.text, selectedTicket!)) {
                            _ticketValidity = TicketValidity.Ok;
                          } else {
                            _ticketValidity = TicketValidity.Invalid;
                          }
                        });
                      },
                      child: Text('Verify'),
                    )
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget validityToCard(TicketValidity validity) {
    Color color;
    String text;
    IconData icon;

    switch (validity) {
      case TicketValidity.Ok:
        color = Colors.green;
        text = 'Validation Successful';
        icon = Icons.check;
        break;
      case TicketValidity.CheckIdentity:
        color = Colors.orange;
        text = 'Suspicious! Check Identity.';
        icon = Icons.perm_identity;
        break;
      case TicketValidity.Invalid:
        color = Colors.red;
        text = 'Ticket Invalid!';
        icon = Icons.warning;
        break;
      default:
        return SizedBox();
    }

    return Card(
      color: color,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white),
            SizedBox(width: 10),
            Text(text, style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}

class BigCard extends StatelessWidget {
  const BigCard({super.key, required this.ticket});

  final Ticket ticket;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.bodyMedium!.copyWith(
      color: theme.colorScheme.onPrimary,
    );

    return Card(
      color: theme.colorScheme.primary,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Container(
              color: Colors.white,
              padding: EdgeInsets.all(8),
              child: QrImageView(
                data: ticket.toData(),
                version: QrVersions.auto,
                size: 200.0,
              ),
            ),
            SizedBox(height: 10),
            Text(ticket.toString(), style: style, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class QrReader extends StatefulWidget {
  const QrReader({super.key});

  @override
  State<QrReader> createState() => _QrReaderState();
}

class _QrReaderState extends State<QrReader> {
  String? _result;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(_result ?? 'Scan a QR Code'),
          SizedBox(height: 20),
          ElevatedButton.icon(
            icon: Icon(Icons.camera_alt),
            label: const Text('Open Scanner'),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => QrCodeScanner(
                  setResult: (result) => setState(() => _result = result),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class QrCodeScanner extends StatelessWidget {
  QrCodeScanner({required this.setResult, super.key});

  final MobileScannerController controller = MobileScannerController();
  final Function(String) setResult;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Scan Ticket")),
      body: MobileScanner(
        controller: controller,
        onDetect: (BarcodeCapture capture) {
          final List<Barcode> barcodes = capture.barcodes;
          for (final barcode in barcodes) {
            if (barcode.rawValue != null) {
              setResult(barcode.rawValue!);
              controller.stop();
              Navigator.of(context).pop();
              break;
            }
          }
        },
      ),
    );
  }
}
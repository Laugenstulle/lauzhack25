import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:crypto/crypto.dart';
import 'dart:math';
import 'dart:convert';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';


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

  var tickets = <Ticket>{};

  void generateTicket(String token) {
    var nonce = Random.secure().toString();
    var bytes = utf8.encode(token + nonce);
    var ticketId = sha256.convert(bytes).toString();
    Ticket ticket = callTicketGenerationServer(ticketId);
    tickets.add(ticket);

    notifyListeners();
  }



}

Ticket callTicketGenerationServer(String ticketId) {
  return new Ticket(
      ticketId: ticketId,
      validFrom: DateTime.fromMillisecondsSinceEpoch(0),
      validUntil: DateTime.now(),
      start: 'Karlsruhe Hbf',
      destination: 'Renens VD',
      price: 42,
  );
}

TicketValidity callTicketValidationServer(StringticketId, location) {
  return TicketValidity.Ok;
}

class Ticket {
  // Data fields
  final String ticketId;
  final DateTime validFrom;
  final DateTime validUntil;
  final String start;
  final String destination;
  final double price;


  // Constructor
  Ticket({
    required this.ticketId,
    required this.validFrom,
    required this.validUntil,
    required this.start,
    required this.destination,
    required this.price,
  });

  @override
  String toString() {
    final DateFormat formatter = DateFormat('dd.MM.yy');
    return "${formatter.format(validFrom)} - ${formatter.format(validUntil)}" +
        "\n$start\n    to\n $destination";
  }

  String toData() {
    return "$ticketId$validFrom$validUntil$start$destination";
  }
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

class TicketGenerator extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    var appState = context.watch<MyAppState>();
    final myController = TextEditingController();

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          TextField(
            controller: myController,
            decoration: const InputDecoration(
              border: UnderlineInputBorder(),
              labelText: 'Enter your anonymous SSB token',

            ),
          ),
          SizedBox(height: 10),
          ElevatedButton(
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) {
                  appState.generateTicket(myController.text);
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
  TicketValidity ticketValidity = TicketValidity.Unkonwn;
  String statusText = "";

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
                          ticketValidity = callTicketValidationServer(selectedTicket!.ticketId, locationController.text);
                          print("checked ticket at ${locationController.text}, ticket validity: $ticketValidity");
                          locationController.clear();
                          },
                        child: Text('check ticket'),
                      ),
                    ],
                  ),
                  Text("$ticketValidity"),

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
          children: [
            Expanded(
              child: QrImageView(
                data: ticket.toData(),
                padding: EdgeInsets.all(5.0),
                version: QrVersions.auto,
                backgroundColor: Colors.white,
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

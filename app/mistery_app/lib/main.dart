import 'package:english_words/english_words.dart';
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
        title: 'Namer App',
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
        page = TicketDropdownScreen();
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

class TicketChecker extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    var appState = context.watch<MyAppState>();
    var selectedTicket = 0;

    if (appState.tickets.isEmpty) {
      return Center(
        child: Text('No tickets to check!'),
      );
    }

    return ListView(
      children: [
        Padding(
          padding: const EdgeInsets.all(20),
          child: Text('TicketViewer')
        ),
      ],
    );
  }
}

class TicketDropdownScreen extends StatefulWidget {
  @override
  _TicketDropdownScreenState createState() => _TicketDropdownScreenState();
}

class _TicketDropdownScreenState extends State<TicketDropdownScreen> {


  Ticket? selectedTicket;

  @override
  Widget build(BuildContext context) {
    var appState = context.watch<MyAppState>();
    var tickets = appState.tickets;

    if (appState.tickets.isEmpty) {
      return Center(
        child: Text('No tickets to check!'),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Select a Ticket'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('Select a Ticket'),
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
                  child: Text(ticket.start),
                );
              }).toList(),
            ),
            SizedBox(height: 20),
            if (selectedTicket != null)
              Column(
                children: [
                  BigCard(ticket: selectedTicket!,)
                ],
              ),
          ],
        ),
      ),
    );
  }
}


// Define a custom Form widget.
class MyCustomForm extends StatefulWidget {
  const MyCustomForm({super.key});

  @override
  State<MyCustomForm> createState() => _MyCustomFormState();
}

// Define a corresponding State class.
// This class holds the data related to the Form.
class _MyCustomFormState extends State<MyCustomForm> {
  // Create a text controller and use it to retrieve the current value
  // of the TextField.
  final myController = TextEditingController();

  @override
  void dispose() {
    // Clean up the controller when the widget is disposed.
    myController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Retrieve Text Input')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: TextField(controller: myController),
      ),
      floatingActionButton: FloatingActionButton(
        // When the user presses the button, show an alert dialog containing
        // the text that the user has entered into the text field.
        onPressed: () {
          showDialog(
            context: context,
            builder: (context) {
              return AlertDialog(
                // Retrieve the text the that user has entered by using the
                // TextEditingController.
                content: Text(myController.text),
              );
            },
          );
        },
        tooltip: 'Show me the value!',
        child: const Icon(Icons.text_fields),
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

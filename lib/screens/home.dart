import 'dart:async';
import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:mapbox_gl/mapbox_gl.dart';
import 'package:flutter/services.dart';
import 'package:sliding_sheet/sliding_sheet.dart';
import '/commons/globals.dart';
import '/commons/location_utils.dart';
import '/widgets/home_controls.dart';
import '/widgets/home_sidebar.dart';
import '/api/stop_query_handler.dart';
import '/models/stop.dart';


class HomeScreen extends StatefulWidget {
  @override
  _HomeScreenState createState() => _HomeScreenState();
}


class _HomeScreenState extends State<HomeScreen> {
  final _mapCompleter = Completer<MapboxMapController>();

  final _styleCompleter = Completer<void>();

  late final MapboxMapController _mapController;

  final _stopQueryHandler = StopQueryHandler();

  final _sheetController = SheetController();

  static const double _initialSheetSize = 0.4;

  final _selectedMarker = ValueNotifier<Symbol?>(null);

  @override
  void initState() {
    super.initState();
    // update native ui colors
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
      // TODO: revisit this when https://github.com/flutter/flutter/pull/81303 lands
      statusBarColor: Colors.black.withOpacity(0.25),
      systemNavigationBarColor: Colors.black.withOpacity(0.25),
      statusBarIconBrightness: Brightness.light,
    ));
    // wait for map creation to finish
    _mapCompleter.future.then(_initMap);
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      drawer: HomeSidebar(),
      // use builder to get scaffold context
      body: Builder(builder: (context) => Stack(
        fit: StackFit.expand,
        children: <Widget>[
          MapboxMap(
            // dispatch camera change events
            trackCameraPosition: true,
            compassEnabled: false,
            accessToken: MAPBOX_API_TOKEN,
            styleString: MAPBOX_STYLE_URL,
            myLocationEnabled: true,
            tiltGesturesEnabled: false,
            initialCameraPosition: CameraPosition(
              zoom: 15.0,
              target: LatLng(50.8261, 12.9278),
            ),
            onMapCreated: _mapCompleter.complete,
            onStyleLoadedCallback: _styleCompleter.complete,
            onMapClick: _onMapClick,
            onCameraIdle: _onCameraIdle,
          ),
          FutureBuilder(
            future: _mapCompleter.future,
            builder: (BuildContext context, AsyncSnapshot<MapboxMapController> snapshot) {
              // only show controls when map creation finished
              return AnimatedSwitcher(
                duration: Duration(milliseconds: 1000),
                child: snapshot.hasData ?
                  HomeControls(
                    mapController: snapshot.data!,
                    buttonStyle: ElevatedButton.styleFrom(
                      primary: Colors.white,
                      onPrimary: Colors.orange,
                      shape: CircleBorder(),
                      padding: EdgeInsets.all(10)
                    )
                  ) :
                  Container(
                    color: Colors.white
                  )
              );
            }
          ),
          SlidingSheet(
            controller: _sheetController,
            addTopViewPaddingOnFullscreen: true,
            elevation: 8,
            cornerRadius: 25,
            cornerRadiusOnFullscreen: 0,
            liftOnScrollHeaderElevation: 8,
            closeOnBackButtonPressed: true,
            duration: const Duration(milliseconds: 300),
            snapSpec: const SnapSpec(
              snap: true,
              snappings: [_initialSheetSize, 1.0],
              positioning: SnapPositioning.relativeToAvailableSpace,
              initialSnap: 0
            ),
            headerBuilder: (context, state) {
              return Container(
                color: Colors.white,
                height: 50,
                width: double.infinity,
                alignment: Alignment.center,
                child: Text(_selectedMarker.value?.data?['name'] ?? 'Unknown stop name')
              );
            },
            builder: (context, state) {
              return Container(
                color: Colors.white,
                height: 800,
                child: Center(
                  child: Text('Content')
                ),
              );
            }
          )
        ]
      )),
    );
  }


  _initMap(MapboxMapController controller) async {
    // store reference to controller
    _mapController = controller;

    _moveToUserLocation();

    _mapController.onSymbolTapped.add(_onSymbolTap);

    _stopQueryHandler.stops.listen(addStopsToMap);
  }


  void _onCameraIdle() async {
    // await _mapController and style loaded callback
    await _mapCompleter.future;
    await _styleCompleter.future;

    if (_mapController.cameraPosition != null) {
      _stopQueryHandler.update(_mapController.cameraPosition!);
    }
  }


  _onMapClick(Point point, LatLng location) async {
    // close bottom sheet if available
    _sheetController.hide();
    // deselect the current marker
    _deselectCurrentSymbol();
  }


  void _onSymbolTap(Symbol symbol) {
    _deselectCurrentSymbol();
    _selectSymbol(symbol);

    _sheetController.rebuild();
    _sheetController.snapToExtent(_initialSheetSize);

    // move camera to symbol
    // padding is not available for newLatLng()
    // therefore use newLatLngBounds as workaround
    final location = symbol.options.geometry!;
    const extend =  LatLng(0.001, 0.001);
    final paddingBottom = (MediaQuery.of(context).size.height - MediaQuery.of(context).padding.top) * _initialSheetSize;
    _mapController.animateCamera(CameraUpdate.newLatLngBounds(
      LatLngBounds(southwest: location - extend, northeast: location + extend),
      bottom: paddingBottom
    ));
  }


  /// Deselect a given symbol on the map

  void _deselectSymbol(Symbol symbol) {
    _mapController.updateSymbol(symbol, SymbolOptions(
      iconImage: 'assets/symbols/bus_stop.png'
    ));
    // unset variable
    _selectedMarker.value = null;
  }


  /// Deselect the last selected symbol on the map

  void _deselectCurrentSymbol() {
    if (_selectedMarker.value != null) {
      _deselectSymbol(_selectedMarker.value!);
    }
  }


  /// Select a given symbol on the map
  /// This pushes it to the _selectedMarker ValueNotifier and changes its icon

  void _selectSymbol(Symbol symbol) {
    // ignore if the symbol is already selected
    if (_selectedMarker.value == symbol) {
      return;
    }
    _mapController.updateSymbol(symbol, SymbolOptions(
      iconImage: 'assets/symbols/bus_stop_selected.png'
    ));
    _selectedMarker.value = symbol;
  }


  /// Update the current map view position to a given location

  Future<void> _moveTo(LatLng location) async {
    await _mapController.animateCamera(CameraUpdate.newLatLng(location));
  }


  /// Acquire current location and update map view position
  /// Returns false if the location couldn't be acquired otherwise true

  Future<bool> _moveToUserLocation() async {
    final location = await acquireCurrentLocation();
    if (location != null) {
      await _moveTo(location);
      return true;
    }
    return false;
  }


  /// Add a given list of Stops as symbols to the map

  void addStopsToMap(Iterable<Stop> result) async {
    final data = <Map<String, String>>[];
    final symbols = <SymbolOptions>[];

    for (final stop in result) {
      symbols.add(SymbolOptions(
        geometry: stop.location,
        iconImage: 'assets/symbols/bus_stop.png',
        iconSize: 0.5,
        iconAnchor: 'bottom'
      ));
      data.add({
        "dhid": stop.dhid,
        "name": stop.name
      });
    }

    _mapController.addSymbols(symbols, data);
  }

  @override
  void dispose() {
    super.dispose();
    _mapController.dispose();
    _stopQueryHandler.dispose();
  }
}
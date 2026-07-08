import 'package:flutter/foundation.dart';

const String _apiBaseUrlOverride = String.fromEnvironment('API_BASE_URL');

String get baseUrl {
	if (_apiBaseUrlOverride.isNotEmpty) {
		return _apiBaseUrlOverride;
	}

	if (kIsWeb) {
		return 'http://localhost:5000/api';
	}

	switch (defaultTargetPlatform) {
		case TargetPlatform.android:
			return 'http://10.0.2.2:5000/api';
		default:
			return 'http://localhost:5000/api';
	}
}

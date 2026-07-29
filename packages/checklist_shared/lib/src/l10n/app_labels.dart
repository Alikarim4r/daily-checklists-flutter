import '../data/ui_labels.dart';

const supportedLanguages = ['en', 'ar', 'bn', 'hi', 'ml', 'tl', 'ta'];

const languageDisplayNames = {
  'en': 'English',
  'ar': 'العربية',
  'bn': 'বাংলা',
  'hi': 'हिन्दी',
  'ml': 'മലയാളം',
  'tl': 'Tagalog',
  'ta': 'தமிழ்',
};

bool isRtlLanguage(String language) => language == 'ar';

class AppLabels {
  AppLabels(this.language);

  final String language;

  Map<String, String> get _map =>
      kUiLabels[language] ?? kUiLabels['en'] ?? const {};

  String call(String key, [String fallback = '']) =>
      _map[key] ?? kUiLabels['en']?[key] ?? fallback;

  String get title => call('title', 'Facility Daily Inspection System');
  String get technicianVersion => call('technicianVersion', 'Technician');
  String get building => call('building', 'Building');
  String get technician => call('technician', 'Technician');
  String get date => call('date', 'Date');
  String get time => call('time', 'Time');
  String get signature => call('signature', 'Signature');
  String get clear => call('clear', 'Clear');
  String get submit => call('submit', 'Submit');
  String get remarks => call('remarks', 'Remarks');
  String get yes => call('yes', 'Yes');
  String get no => call('no', 'No');
  String get na => call('na', 'N/A');
  String get takePhoto => call('takePhoto', 'Take photo');
  String get login => call('login', 'Login');
  String get email => call('email', 'Email');
  String get password => call('password', 'Password');
  String get loginButton => call('loginButton', 'Sign In');
  String get logout => call('logout', 'Logout');
  String get saving => call('saving', 'Saving...');
  String get success => call('success', 'Saved successfully');
  String get error => call('error', 'Error');
  String get save => call('save', 'Save');
  String get cancel => call('cancel', 'Cancel');
  String get addItem => call('addItem', 'Add item');
  String get editItem => call('editItem', 'Edit item');
  String get deleteItem => call('deleteItem', 'Delete item');
  String get inspectionItems => call('inspectionItems', 'Inspection items');
  String get photoRequired => call('photoRequired', 'Photo required');
  String get uploadingImages => call('uploadingImages', 'Uploading images...');
  String get newRecord => call('newRecord', 'New record');
  String get editingRecord => call('editingRecord', 'Editing record');
  String get pin => call('pin', 'PIN');
  String get issuePhoto => call('issuePhoto', 'Issue photo');
  String get fixPhoto => call('fixPhoto', 'Fix photo');
  String get gallery => call('gallery', 'Gallery');
  String get openCamera => call('openCamera', 'Open camera');
  String get removePhoto => call('removePhoto', 'Remove');
  String get previousAnswer => call('previousAnswer', 'Previous');
  String get persistentProblem =>
      call('persistentProblem', 'Persistent problem');
}

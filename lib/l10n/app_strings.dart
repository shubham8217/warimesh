// WariMesh — user-facing text, Marathi first.
//
// The people this app is for are Warkaris walking to Pandharpur, the
// volunteers staffing camps along the route, and the Dindi Leads who know
// who is walking with whom. They speak Marathi. An English emergency app
// with Marathi bolted on is not the same product as an app that was written
// for the Wari, and the difference shows up exactly when it matters most —
// somebody tired, elderly, frightened, holding a phone in a crowd.
//
// Two rules run through everything here:
//
//  1. USER-FACING TEXT IS MARATHI. Diagnostics are not. Every appendLog()
//     line, every debugPrint, every activity-log entry stays English: those
//     are read by whoever is debugging a mesh at 3am, not by a pilgrim.
//     That line is deliberate and worth keeping.
//
//  2. TECHNICAL TERMS STAY AS THEY ARE. SOS, WariMesh, GPS, BLE, Mesh ID
//     are recognised far more reliably in their familiar form than in any
//     invented Marathi equivalent. Translating "SOS" would make the app
//     harder to use, not more local.
//
// Architecture: [AppStrings] is the contract, [MarathiStrings] is the
// default, and [EnglishStrings] exists so a language switch is a one-line
// change rather than a rewrite of every widget. Swap via [setAppLanguage].
// A proper Localizations delegate keyed off the device locale is the
// natural next step; the point of doing it this way now is that no screen
// has to change when that happens — they all read from `t`.

import 'package:flutter/material.dart';

import '../database_service.dart';
import '../models.dart';
import '../theme.dart';

/// The language the whole app is currently rendering in.
///
/// A notifier rather than a plain global because changing language has to
/// repaint every screen that is already built — main.dart listens to this
/// and rebuilds the MaterialApp beneath it. A bare mutable global would
/// change the strings and leave the visible UI stale until something else
/// happened to trigger a rebuild, which is the sort of half-applied setting
/// that makes people tap it repeatedly.
final ValueNotifier<AppStrings> appLanguage = ValueNotifier<AppStrings>(
  const MarathiStrings(),
);

/// Marathi by default — see the note at the top of this file.
AppStrings get t => appLanguage.value;

void setAppLanguage(AppStrings strings) => appLanguage.value = strings;

/// Persisted as a short code (see SettingsDb) rather than a class name, so
/// the stored value stays readable and stable if these classes are ever
/// renamed.
const String kLanguageMarathi = 'mr';
const String kLanguageEnglish = 'en';

AppStrings appStringsForCode(String? code) =>
    code == kLanguageEnglish ? const EnglishStrings() : const MarathiStrings();

/// Devanagari numerals, for the numbers a Warkari reads.
///
/// Deliberately NOT applied everywhere: Mesh IDs, msgIds, timestamps,
/// coordinates and anything in the activity log keep Arabic numerals,
/// because those are read for technical comparison ("is this the same
/// packet?") where the familiar digits are genuinely clearer.
String mrNum(Object value) {
  const digits = ['०', '१', '२', '३', '४', '५', '६', '७', '८', '९'];
  final buffer = StringBuffer();
  for (final rune in value.toString().runes) {
    final ch = String.fromCharCode(rune);
    final code = rune - 48;
    buffer.write(code >= 0 && code <= 9 ? digits[code] : ch);
  }
  return buffer.toString();
}

abstract class AppStrings {
  const AppStrings();

  /// What gets written to storage, and what names this language in the
  /// language picker — in its OWN language, always. Somebody who has landed
  /// in a language they cannot read must still be able to find their way
  /// out, and "English" written in Devanagari helps nobody do that.
  String get languageCode;
  String get languageName;

  // ---- roles and people -------------------------------------------------
  String get warkari;
  String get volunteer;
  String get dindiLead;
  String get dindi;

  /// "मदतीसाठी येत आहे" / "समन्वय करत आहे" — a Lead coordinates, everyone
  /// else responds. Takes the role word this app already computed.
  String responderVerbFor(String role);

  /// The role word for a Mesh ID, localized. Mirrors responderRoleLabel()
  /// in models.dart, which stays English as the canonical/diagnostic form.
  String roleLabel(String meshId, {required bool isDindiLead});

  // ---- SOS --------------------------------------------------------------
  String get sosSend;
  String get sosHold;
  String get sosKeepHolding;
  String get sosSending;
  String get sosSent;
  String get sosReasonQuestion;
  String get sosReasonSubtitle;
  String get sosSendWithoutSaying;
  String get sosPropagatedDindi;
  String get sosPropagatedVolunteers;
  String sosCooldown(int seconds);
  String get lostPersonAlert;

  /// The emergency type, e.g. "वैद्यकीय मदत". Takes a kSosReason* constant.
  String sosReason(int reason);

  // ---- alert lifecycle --------------------------------------------------
  String get statusUnattended;
  String get statusTaken;
  String get statusClosed;
  String get statusOpen;
  String get imResponding;
  String get joinAnyway;
  String get closeAlert;
  String get reopen;
  String get respond;
  String get coordinate;
  String get helpIsComing;
  String get yourAlertIsOut;
  String get youAreResponding;
  String get responseQueue;
  String get nothingWaiting;
  String get nothingWaitingDetail;

  // ---- missing person ---------------------------------------------------
  String get missingWarkari;
  String get missingPerson;
  String get spotted;
  String get found;
  String get iveSpottedThem;
  String get reportAnotherSighting;
  String get statusSearching;
  String get statusSpotted;
  String get lookingFor;
  String spottedBy(String who, String? at);
  String get positionSentWithSighting;
  String get noPositionWithSighting;

  // ---- Dindi ------------------------------------------------------------
  String get myDindi;
  String get dindiEmergencies;
  String get sosFromYourDindi;
  String get missingFromYourDindi;
  String get iAmDindiLead;
  String get iAmDindiLeadDetail;
  String get member;
  String get membersNearby;

  // ---- Seva / help points -----------------------------------------------
  String get seva;
  String get nearbySeva;
  String get listeningForSeva;
  String get view;
  String get sevaDiscoveredThroughMesh;
  String get announceHelpPoint;
  String get announce;
  String get cancel;
  String get offDuty;
  String get notAtHelpPoint;
  String get tapToAnnounce;
  String get pilgrimsCanSeeHelp;
  String get imGoingThere;
  String get youreOnYourWay;
  String get openDirections;
  String get sharedThroughWariMesh;
  String get receivedDirectly;
  String get lastUpdated;

  /// A help point type, e.g. "वैद्यकीय सेवा". Takes a kStation* constant.
  String station(int station);

  /// Open / closed / limited. Takes a kHelpStatus* constant.
  String helpStatus(int status);

  String announceConfirmBody(String stationName);
  String helpPointNowVisible(String stationName);
  String get helpPointClosed;
  String relayedThrough(int hops);

  // ---- advisories -------------------------------------------------------
  String get advisory;
  String advisoryCount(int n);
  String get advisoriesFromVolunteers;
  String moreTapToRead(int n);

  // ---- location ---------------------------------------------------------
  String distance(double metres);
  String direction(double bearing);

  /// The one line someone reads to decide whether to walk. Never invents a
  /// distance — see HelpPointRecord.whereLabel for the same rule in English.
  String whereLabel({
    required bool hasLocation,
    double? distanceMetres,
    double? bearingDegrees,
  });

  String get locationUnavailable;
  String get positionKnownNoFixHere;
  String get noPositionOnThisAlert;

  // ---- mesh / status ----------------------------------------------------
  String get meshConnected;
  String get meshNotConnected;
  String get bluetoothOff;

  /// The menu entry that opens the language picker.
  String get language;

  // ---- the rest of the user-facing surface -----------------------------
  // Everything below was briefly hardcoded straight into widgets while this
  // layer was being built, which meant those strings ignored the language
  // switch entirely -- the app sat in English with Marathi fragments
  // stranded across it. Kept here so there is exactly one place where a
  // language can be complete, or visibly incomplete.
  String get greeting;
  String get account;
  String get signOut;
  String get sendAlertTitle;
  String get holdSuffix;
  String get lastSent;
  String get alertNowSent;
  String openCount(int n);
  String get sosSubtitle;
  String get missingTitle;
  String get missingSubtitleIdle;
  String missingSubtitleActive(int n);
  String get you;
  String get joinDifferentDindi;
  String get leaveDindi;
  String get createOrJoinDindi;
  String get place;
  String get time;
  String announceQuestion(String stationName);
  String stationAvailable(String stationName);
  String stationNearby(String stationName);
  String get noMapsApp;
  String get helpPointPrivacyNote;
  String alertFinished(String age);
  String respondingToYours(String who);
  String alertOutDetail(String age);

  // Notifications: lock-screen text is user-facing too.
  String notifNeedsHelp(String from, String where);
  String notifLookFor(String name, String age, String from, String where);
  String notifSomeoneMissing(String from, String where);
  String get notifAgePrefix;
  String get notifMissingTitle;
  String get notifSosTitle;
  String notifAdvisoryTitle(String who);
  String get notifHelpComingTitle;
  String notifHelpComingBody(String who);
  String get notifSightingTitle;
  String notifSightingBody(String who, String subject);
  String get notifThePersonYouReported;

  // ---- volunteer network overview ---------------------------------------
  // Every label here is worded to say what the mesh can actually see. See
  // WariNetworkStats: these are counts of what THIS phone can hear, never a
  // census of the Wari, and the wording must not let anyone read them that
  // way.
  String get wariNetwork;
  String get networkActive;
  String get networkDown;
  String get dindisHeading;
  String get participants;
  String get participantsCaption;
  String get dindiLeads;
  String get volunteers;
  String get warkaris;
  String get activeSos;
  String get missingWarkaris;
  String get sevaPoints;
  String get mukkaam;
  String get viewDindis;
  String get noDindisHeard;
  String get noDindisHeardDetail;
  String get noEmergencies;
  String get unavailable;
  String get dindiCode;
  String get visibleInWariMesh;
  String get visibleInWariMeshCaption;
  String get leadNearby;
  String get leadLastSeen;
  String get lastKnownLocation;
  String get lastUpdate;
  String get viewDindiDetails;
  String get viewActiveIncidents;
  String get nearbySevaShort;
  String get mukkaamNoSource;
  String get dindiNameUnknown;
  String get participantsSingleHopNote;

  // ---- time -------------------------------------------------------------
  String ageLabel(DateTime since);
}

class MarathiStrings extends AppStrings {
  const MarathiStrings();

  @override
  String get languageCode => kLanguageMarathi;
  @override
  String get languageName => 'मराठी';

  @override
  String get warkari => 'वारकरी';
  @override
  String get volunteer => 'स्वयंसेवक';
  @override
  String get dindiLead => 'दिंडी प्रमुख';
  @override
  String get dindi => 'दिंडी';

  @override
  String responderVerbFor(String role) =>
      role == dindiLead ? 'समन्वय करत आहे' : 'मदतीसाठी येत आहे';

  @override
  String roleLabel(String meshId, {required bool isDindiLead}) {
    if (meshId.startsWith('V')) return volunteer;
    return isDindiLead ? dindiLead : warkari;
  }

  // SOS stays "SOS" — see the note at the top of this file.
  @override
  String get sosSend => 'SOS पाठवा';
  @override
  String get sosHold => 'दाबून ठेवा';
  @override
  String get sosKeepHolding => 'दाबून ठेवा…';
  @override
  String get sosSending => 'पाठवत आहे…';
  @override
  String get sosSent => 'तुमचा SOS पाठवला आहे';
  @override
  String get sosReasonQuestion => 'मदत कशासाठी हवी आहे?';
  @override
  String get sosReasonSubtitle =>
      'तुमचा SOS कोणत्याही परिस्थितीत जाईल. हे सांगितल्याने मदत करणाऱ्याला काय आणायचे ते कळेल.';
  @override
  String get sosSendWithoutSaying => 'न सांगता पाठवा';
  @override
  String get sosPropagatedDindi => 'तुमच्या दिंडीपर्यंत पोहोचवले';
  @override
  String get sosPropagatedVolunteers => 'जवळच्या स्वयंसेवकांपर्यंत पोहोचवले';
  @override
  String sosCooldown(int seconds) =>
      '${mrNum(seconds)} सेकंद थांबा — रेडिओ मोकळा ठेवण्यासाठी';
  @override
  String get lostPersonAlert => 'हरवलेली व्यक्ती';

  @override
  String sosReason(int reason) {
    switch (reason) {
      case kSosReasonMedical:
        return 'वैद्यकीय मदत';
      case kSosReasonHeat:
        return 'उष्माघात / पाणी कमी झाले';
      case kSosReasonChild:
        return 'मूल / व्यक्ती हरवली';
      case kSosReasonElderly:
        return 'ज्येष्ठ / असहाय व्यक्ती';
      case kSosReasonLost:
        return 'दिंडीपासून वेगळे झाले';
      case kSosReasonSafety:
        return 'धोका / सुरक्षिततेची समस्या';
      case kSosReasonOther:
        return 'इतर';
      default:
        return 'आपत्कालीन मदत';
    }
  }

  @override
  String get statusUnattended => 'मदत मिळालेली नाही';
  @override
  String get statusTaken => 'प्रतिसाद मिळाला';
  @override
  String get statusClosed => 'बंद झाले';
  @override
  String get statusOpen => 'प्रलंबित';
  @override
  String get imResponding => 'मी मदतीसाठी येत आहे';
  @override
  String get joinAnyway => 'तरीही सहभागी व्हा';
  @override
  String get closeAlert => 'बंद करा';
  @override
  String get reopen => 'पुन्हा सुरू करा';
  @override
  String get respond => 'मदतीसाठी प्रतिसाद द्या';
  @override
  String get coordinate => 'समन्वय करा';
  @override
  String get helpIsComing => 'मदत येत आहे';
  @override
  String get yourAlertIsOut => 'तुमचा SOS पाठवला आहे';
  @override
  String get youAreResponding => 'तुम्ही मदतीसाठी जात आहात';
  @override
  String get responseQueue => 'प्रतिसाद यादी';
  @override
  String get nothingWaiting => 'काहीही प्रलंबित नाही';
  @override
  String get nothingWaitingDetail =>
      'या फोनवर अजून कोणतीही सूचना आलेली नाही. फोन पार्श्वभूमीत ऐकत राहतो — जे येईल ते इथे दिसेल.';

  @override
  String get missingWarkari => 'हरवलेला वारकरी';
  @override
  String get missingPerson => 'हरवलेली व्यक्ती';
  @override
  String get spotted => 'दिसला';
  @override
  String get found => 'सापडला';
  @override
  String get iveSpottedThem => 'मला दिसले';
  @override
  String get reportAnotherSighting => 'पुन्हा दिसल्याचे कळवा';
  @override
  String get statusSearching => 'शोध सुरू आहे';
  @override
  String get statusSpotted => 'वारकरी दिसला';
  @override
  String get lookingFor => 'शोधत आहोत';
  @override
  String spottedBy(String who, String? at) =>
      at == null ? '$who यांना दिसले' : '$who यांना दिसले · $at';
  @override
  String get positionSentWithSighting => 'ठिकाणासह कळवले';
  @override
  String get noPositionWithSighting => 'ठिकाण कळवलेले नाही';

  @override
  String get myDindi => 'माझी दिंडी';
  @override
  String get dindiEmergencies => 'दिंडीतील आपत्कालीन घटना';
  @override
  String get sosFromYourDindi => 'तुमच्या दिंडीतील SOS';
  @override
  String get missingFromYourDindi => 'तुमच्या दिंडीतील हरवलेला वारकरी';
  @override
  String get iAmDindiLead => 'मी या दिंडीचा प्रमुख आहे';
  @override
  String get iAmDindiLeadDetail =>
      'या दिंडीतील SOS तुम्हाला आपत्कालीन घटना म्हणून दिसेल, म्हणजे तुम्ही प्रतिसाद देऊ शकाल किंवा समन्वय करू शकाल.';
  @override
  String get member => 'सदस्य';
  @override
  String get membersNearby => 'जवळचे सदस्य';

  @override
  String get seva => 'सेवा';
  @override
  String get nearbySeva => 'जवळची सेवा';
  @override
  String get listeningForSeva => 'जवळच्या सेवेचा शोध सुरू आहे…';
  @override
  String get view => 'पहा';
  @override
  String get sevaDiscoveredThroughMesh =>
      'WariMesh द्वारे सापडले — इंटरनेटशिवाय.';
  @override
  String get announceHelpPoint => 'सेवा जाहीर करा';
  @override
  String get announce => 'जाहीर करा';
  @override
  String get cancel => 'रद्द करा';
  @override
  String get offDuty => 'सेवा बंद करा';
  @override
  String get notAtHelpPoint => 'सेवा केंद्रावर नाही';
  @override
  String get tapToAnnounce => 'सेवा जाहीर करण्यासाठी दाबा';
  @override
  String get pilgrimsCanSeeHelp => 'जवळच्या वारकऱ्यांना ही सेवा दिसेल';
  @override
  String get imGoingThere => 'मी तिथे जात आहे';
  @override
  String get youreOnYourWay => 'तुम्ही तिकडे निघाला आहात';
  @override
  String get openDirections => 'रस्ता दाखवा';
  @override
  String get sharedThroughWariMesh => 'WariMesh द्वारे मिळाले';
  @override
  String get receivedDirectly => 'थेट स्वयंसेवकाकडून मिळाले';
  @override
  String get lastUpdated => 'शेवटचे कळले';

  @override
  String station(int station) {
    switch (station) {
      case kStationMedical:
        return 'वैद्यकीय सेवा';
      case kStationWater:
        return 'पाणी सेवा';
      case kStationFood:
        return 'अन्न सेवा';
      case kStationLostChildDesk:
        return 'हरवलेले मूल मदत केंद्र';
      case kStationPolice:
        return 'पोलीस मदत';
      case kStationToilet:
        return 'स्वच्छतागृह';
      case kStationNightHalt:
        return 'मुक्काम';
      case kStationCharging:
        return 'मोबाईल चार्जिंग';
      case kStationFirstAid:
        return 'प्राथमिक उपचार';
      case kStationOther:
        return 'मदत केंद्र';
      default:
        return notAtHelpPoint;
    }
  }

  @override
  String helpStatus(int status) {
    switch (status) {
      case kHelpStatusClosed:
        return 'बंद';
      case kHelpStatusLimited:
        return 'मर्यादित जागा';
      default:
        return 'उपलब्ध';
    }
  }

  @override
  String announceConfirmBody(String stationName) =>
      '$stationName जवळच्या WariMesh वापरकर्त्यांना दिसेल — थेट पल्ल्याबाहेरील फोनपर्यंतही, एका फोनकडून दुसऱ्या फोनकडे.\n\n'
      'तुमचे ठिकाणही सोबत जाईल, म्हणजे लोकांना कोणत्या दिशेला यायचे ते कळेल. '
      'Bluetooth प्रसारण सर्वांना दिसते — जवळचे कोणीही ते वाचू शकते.';
  @override
  String helpPointNowVisible(String stationName) =>
      '$stationName आता जवळच्या WariMesh वापरकर्त्यांना दिसत आहे.';
  @override
  String get helpPointClosed => 'सेवा बंद केली.';
  @override
  String relayedThrough(int hops) => hops == 0
      ? 'थेट मिळाले'
      : '${mrNum(hops)} फोनमार्फत तुमच्यापर्यंत पोहोचले';

  @override
  String get advisory => 'सूचना';
  @override
  String advisoryCount(int n) => '${mrNum(n)} सूचना';
  @override
  String get advisoriesFromVolunteers => 'मार्गावरील स्वयंसेवकांकडून.';
  @override
  String moreTapToRead(int n) => 'आणखी ${mrNum(n)} — वाचण्यासाठी दाबा';

  @override
  String distance(double metres) => metres < 1000
      ? '${mrNum(metres.round())} मी. अंतरावर'
      : '${mrNum((metres / 1000).toStringAsFixed(1))} किमी अंतरावर';

  @override
  String direction(double bearing) {
    const points = [
      'उत्तर',
      'ईशान्य',
      'पूर्व',
      'आग्नेय',
      'दक्षिण',
      'नैऋत्य',
      'पश्चिम',
      'वायव्य',
    ];
    return points[(((bearing % 360) + 360) % 360 / 45).round() % 8];
  }

  @override
  String whereLabel({
    required bool hasLocation,
    double? distanceMetres,
    double? bearingDegrees,
  }) {
    if (distanceMetres != null && bearingDegrees != null) {
      return '${distance(distanceMetres)}, ${direction(bearingDegrees)} दिशेला';
    }
    if (distanceMetres != null) return distance(distanceMetres);
    if (hasLocation) return positionKnownNoFixHere;
    return locationUnavailable;
  }

  @override
  String get locationUnavailable => 'ठिकाण उपलब्ध नाही — जवळपासच आहे';
  @override
  String get positionKnownNoFixHere =>
      'ठिकाण माहीत आहे — पण तुमच्या फोनला स्वतःचे ठिकाण मिळालेले नाही';
  @override
  String get noPositionOnThisAlert => 'या सूचनेसोबत ठिकाण आलेले नाही';

  @override
  String get meshConnected => 'नेटवर्क सक्रिय — जवळचे फोन तुम्हाला ऐकू शकतात';
  @override
  String get meshNotConnected => 'अजून जोडलेले नाही';
  @override
  String get bluetoothOff =>
      'Bluetooth बंद आहे — जवळच्या फोनपर्यंत पोहोचण्यासाठी चालू करा';

  @override
  String get language => 'भाषा';

  @override
  String get greeting => 'नमस्कार';
  @override
  String get account => 'खाते';
  @override
  String get signOut => 'बाहेर पडा';
  @override
  String get sendAlertTitle => 'मदतीसाठी सूचना पाठवा';
  @override
  String get holdSuffix => 'दाबून ठेवा';
  @override
  String get lastSent => 'शेवटचे पाठवले';
  @override
  String get alertNowSent => 'पाठवली आहे';
  @override
  String openCount(int n) => '${mrNum(n)} प्रलंबित';
  @override
  String get sosSubtitle => 'जवळच्या फोनना कळवा';
  @override
  String get missingTitle => 'हरवलेले';
  @override
  String get missingSubtitleIdle => 'कळवा किंवा शोधा';
  @override
  String missingSubtitleActive(int n) => '${mrNum(n)} सुरू असलेले शोध';
  @override
  String get you => 'तुम्ही';
  @override
  String get joinDifferentDindi => 'दुसर्या दिंडीत सामील व्हा';
  @override
  String get leaveDindi => 'दिंडी सोडा';
  @override
  String get createOrJoinDindi => 'दिंडी तयार करा किंवा सामील व्हा';
  @override
  String get place => 'ठिकाण';
  @override
  String get time => 'वेळ';
  @override
  String announceQuestion(String stationName) => '$stationName जाहीर करायची?';
  @override
  String stationAvailable(String stationName) => '$stationName उपलब्ध आहे';
  @override
  String stationNearby(String stationName) => '$stationName जवळ आहे';
  @override
  String get noMapsApp => 'या फोनवर नकाशा अ‍ॅप उघडू शकले नाही';
  @override
  String get helpPointPrivacyNote =>
      'Bluetooth प्रसारण सर्वांना दिसते. '
      'हे स्वयंसेवकाने स्वतः जाहीर केलेले '
      'ठिकाण आहे, खासगी संदेश नाही.';
  @override
  String alertFinished(String age) =>
      'तुमची $age पाठवलेली सूचना पूर्ण झाली आहे.';
  @override
  String respondingToYours(String who) =>
      '$who तुमच्या सूचनेला प्रतिसाद देत आहे.';
  @override
  String alertOutDetail(String age) =>
      '$age पाठवली. जवळचे फोन ती पुढे पोहोचवत आहेत. '
      'कोणी प्रतिसाद देताच तुम्हाला कळवले जाईल.';

  @override
  String notifNeedsHelp(String from, String where) =>
      '$from यांना मदत हवी आहे$where';
  @override
  String notifLookFor(String name, String age, String from, String where) =>
      '$name$age यांना शोधा — $from यांनी कळवले$where';
  @override
  String notifSomeoneMissing(String from, String where) =>
      '$from यांनी जवळपास कोणीतरी हरवल्याचे कळवले$where';
  @override
  String get notifAgePrefix => 'वय';
  @override
  String get notifMissingTitle => '🔎 जवळपास कोणीतरी हरवले आहे';
  @override
  String get notifSosTitle => '🆘 SOS आला आहे';
  @override
  String notifAdvisoryTitle(String who) => '📢 सूचना — $who';
  @override
  String get notifHelpComingTitle => 'मदत येत आहे';
  @override
  String notifHelpComingBody(String who) => '$who मदतीसाठी येत आहेत.';
  @override
  String get notifSightingTitle => '👀 वारकरी दिसला';
  @override
  String notifSightingBody(String who, String subject) =>
      '$who यांना $subject दिसले.';
  @override
  String get notifThePersonYouReported => 'तुम्ही कळवलेली हरवलेली व्यक्ती';

  @override
  String get wariNetwork => 'WariMesh नेटवर्क';
  @override
  String get networkActive => 'नेटवर्क सक्रिय';
  @override
  String get networkDown => 'नेटवर्क बंद';
  @override
  String get dindisHeading => 'दिंड्या';
  @override
  String get participants => 'WariMesh सहभागी';
  @override
  String get participantsCaption => 'सध्या दिसणारे WariMesh सहभागी';
  @override
  String get dindiLeads => 'दिंडी प्रमुख';
  @override
  String get volunteers => 'स्वयंसेवक';
  @override
  String get warkaris => 'वारकरी';
  @override
  String get activeSos => 'सक्रिय SOS';
  @override
  String get missingWarkaris => 'हरवलेले वारकरी';
  @override
  String get sevaPoints => 'सेवा केंद्रे';
  @override
  String get mukkaam => 'मुक्काम';
  @override
  String get viewDindis => 'दिंड्या पहा';
  @override
  String get noDindisHeard => 'सध्या कोणतीही दिंडी दिसत नाही';
  @override
  String get noDindisHeardDetail =>
      'जवळच्या फोनवरून दिंडी दिसताच ती इथे येईल. '
      'हा फोन ऐकत राहतो.';
  @override
  String get noEmergencies => 'कोणतीही सक्रिय आपत्कालीन घटना नाही';
  @override
  String get unavailable => 'उपलब्ध नाही';
  @override
  String get dindiCode => 'दिंडी कोड';
  @override
  String get visibleInWariMesh => 'WariMesh मध्ये सध्या दिसणारे';
  @override
  String get visibleInWariMeshCaption =>
      'हा आकडा या फोनला ऐकू येणाऱ्या सहभागींचा आहे — '
      'दिंडीतील एकूण माणसांचा नाही.';
  @override
  String get leadNearby => 'अलीकडे दिसले';
  @override
  String get leadLastSeen => 'शेवटचे दिसले';
  @override
  String get lastKnownLocation => 'शेवटचे ज्ञात ठिकाण';
  @override
  String get lastUpdate => 'शेवटचे अपडेट';
  @override
  String get viewDindiDetails => 'दिंडीची संपूर्ण माहिती';
  @override
  String get viewActiveIncidents => 'सक्रिय घटना पहा';
  @override
  String get nearbySevaShort => 'जवळची सेवा';
  @override
  String get mukkaamNoSource =>
      'मुक्कामाची माहिती WariMesh वर येत नाही. '
      'जवळ जाहीर केलेला मुक्काम असेल तरच दिसेल.';
  @override
  String get dindiNameUnknown =>
      'दिंडीचे नाव WariMesh वर पाठवले जात नाही — फक्त कोड दिसतो.';
  @override
  String get participantsSingleHopNote =>
      'हे आकडे या फोनला थेट ऐकू येणाऱ्या फोनचे आहेत, '
      'संपूर्ण वारीचे नाहीत.';

  @override
  String ageLabel(DateTime since) {
    final mins = DateTime.now().difference(since).inMinutes;
    if (mins < 1) return 'आत्ताच';
    if (mins < 60) return '${mrNum(mins)} मिनिटांपूर्वी';
    final hours = mins ~/ 60;
    if (hours < 24) return '${mrNum(hours)} तासांपूर्वी';
    return '${mrNum(hours ~/ 24)} दिवसांपूर्वी';
  }
}

/// Kept complete and in step with [MarathiStrings] so switching back is one
/// line, not a rewrite. Nothing selects this today — see setAppLanguage.
class EnglishStrings extends AppStrings {
  const EnglishStrings();

  @override
  String get languageCode => kLanguageEnglish;
  @override
  String get languageName => 'English';

  @override
  String get warkari => 'Warkari';
  @override
  String get volunteer => 'Volunteer';
  @override
  String get dindiLead => 'Dindi Lead';
  @override
  String get dindi => 'Dindi';

  @override
  String responderVerbFor(String role) =>
      role == dindiLead ? 'is coordinating' : 'is responding';

  @override
  String roleLabel(String meshId, {required bool isDindiLead}) =>
      responderRoleLabel(meshId, isDindiLead: isDindiLead);

  @override
  String get sosSend => 'Send SOS';
  @override
  String get sosHold => 'HOLD';
  @override
  String get sosKeepHolding => 'Keep holding…';
  @override
  String get sosSending => 'Broadcasting over the mesh…';
  @override
  String get sosSent => 'SOS SENT';
  @override
  String get sosReasonQuestion => 'What do you need help with?';
  @override
  String get sosReasonSubtitle =>
      'Your alert goes out either way. This tells whoever answers what to bring.';
  @override
  String get sosSendWithoutSaying => 'Send without saying';
  @override
  String get sosPropagatedDindi => 'Alert propagated to your Dindi';
  @override
  String get sosPropagatedVolunteers => 'Alert propagated to nearby volunteers';
  @override
  String sosCooldown(int seconds) =>
      'Cooling down — wait ${seconds}s so the radio stays free';
  @override
  String get lostPersonAlert => 'Lost Person';

  @override
  String sosReason(int reason) => sosReasonLabel(reason);

  @override
  String get statusUnattended => 'Unattended';
  @override
  String get statusTaken => 'Taken';
  @override
  String get statusClosed => 'Closed';
  @override
  String get statusOpen => 'Open';
  @override
  String get imResponding => "I'm responding";
  @override
  String get joinAnyway => 'Join anyway';
  @override
  String get closeAlert => 'Close';
  @override
  String get reopen => 'Reopen';
  @override
  String get respond => 'RESPOND';
  @override
  String get coordinate => 'COORDINATE';
  @override
  String get helpIsComing => 'Help is coming';
  @override
  String get yourAlertIsOut => 'Your alert is out';
  @override
  String get youAreResponding => 'You are responding';
  @override
  String get responseQueue => 'Response queue';
  @override
  String get nothingWaiting => 'Nothing waiting';
  @override
  String get nothingWaitingDetail =>
      'No alerts have reached this phone. It stays listening in the background — anything that arrives lands here.';

  @override
  String get missingWarkari => 'Missing Warkari';
  @override
  String get missingPerson => 'Missing person';
  @override
  String get spotted => 'SPOTTED';
  @override
  String get found => 'FOUND';
  @override
  String get iveSpottedThem => "I'VE SPOTTED THEM";
  @override
  String get reportAnotherSighting => 'Report another sighting';
  @override
  String get statusSearching => 'Searching';
  @override
  String get statusSpotted => 'Spotted';
  @override
  String get lookingFor => 'Looking for';
  @override
  String spottedBy(String who, String? at) => at == null
      ? '$who reported seeing them'
      : '$who reported seeing them · $at';
  @override
  String get positionSentWithSighting => 'Position sent with the sighting';
  @override
  String get noPositionWithSighting => 'No position sent with the sighting';

  @override
  String get myDindi => 'My Dindi';
  @override
  String get dindiEmergencies => 'Dindi Emergencies';
  @override
  String get sosFromYourDindi => 'SOS FROM YOUR DINDI';
  @override
  String get missingFromYourDindi => 'MISSING WARKARI FROM YOUR DINDI';
  @override
  String get iAmDindiLead => 'I am the Dindi Lead';
  @override
  String get iAmDindiLeadDetail =>
      'An SOS from this Dindi will be shown to you as a Dindi Emergency, so you can respond or coordinate.';
  @override
  String get member => 'Member';
  @override
  String get membersNearby => 'MEMBERS NEARBY';

  @override
  String get seva => 'Seva';
  @override
  String get nearbySeva => 'Nearby Seva';
  @override
  String get listeningForSeva => 'Listening for nearby seva...';
  @override
  String get view => 'VIEW';
  @override
  String get sevaDiscoveredThroughMesh =>
      'Discovered through WariMesh — no internet involved.';
  @override
  String get announceHelpPoint => 'Announce help point';
  @override
  String get announce => 'Announce';
  @override
  String get cancel => 'Cancel';
  @override
  String get offDuty => 'Off duty';
  @override
  String get notAtHelpPoint => 'Not at a help point';
  @override
  String get tapToAnnounce => 'Tap to announce a help point';
  @override
  String get pilgrimsCanSeeHelp => 'Pilgrims in range can see help is here';
  @override
  String get imGoingThere => "I'm going there";
  @override
  String get youreOnYourWay => "You're on your way";
  @override
  String get openDirections => 'Open directions';
  @override
  String get sharedThroughWariMesh => 'Shared through WariMesh';
  @override
  String get receivedDirectly => 'Heard directly from the volunteer';
  @override
  String get lastUpdated => 'Last updated';

  @override
  String station(int station) => stationLabel(station);

  @override
  String helpStatus(int status) => helpStatusLabel(status);

  @override
  String announceConfirmBody(String stationName) =>
      '$stationName will be visible to nearby WariMesh users — including phones '
      'out of direct range, relayed hop by hop.\n\n'
      'Your position goes out with it, so people can be told which way to walk. '
      'A Bluetooth broadcast is public — anyone in range can read it.';
  @override
  String helpPointNowVisible(String stationName) =>
      '$stationName is now visible to nearby WariMesh users.';
  @override
  String get helpPointClosed => 'Help point closed.';
  @override
  String relayedThrough(int hops) => hops == 0
      ? 'Heard directly'
      : 'Relayed through $hops phone${hops == 1 ? '' : 's'} to reach you';

  @override
  String get advisory => 'Advisory';
  @override
  String advisoryCount(int n) => '$n advisories';
  @override
  String get advisoriesFromVolunteers => 'From volunteers along the route.';
  @override
  String moreTapToRead(int n) => '+$n more — tap to read';

  @override
  String distance(double metres) => metres < 1000
      ? '${metres.round()} m away'
      : '${(metres / 1000).toStringAsFixed(1)} km away';

  @override
  String direction(double bearing) {
    const points = [
      'north',
      'north-east',
      'east',
      'south-east',
      'south',
      'south-west',
      'west',
      'north-west',
    ];
    return points[(((bearing % 360) + 360) % 360 / 45).round() % 8];
  }

  @override
  String whereLabel({
    required bool hasLocation,
    double? distanceMetres,
    double? bearingDegrees,
  }) {
    if (distanceMetres != null && bearingDegrees != null) {
      return '${distance(distanceMetres)}, to your ${direction(bearingDegrees)}';
    }
    if (distanceMetres != null) return distance(distanceMetres);
    if (hasLocation) return positionKnownNoFixHere;
    return locationUnavailable;
  }

  @override
  String get locationUnavailable =>
      'Location unavailable — nearby through WariMesh';
  @override
  String get positionKnownNoFixHere =>
      'Position known — no fix on this phone to measure from';
  @override
  String get noPositionOnThisAlert =>
      'No position — this alert came without one';

  @override
  String get meshConnected =>
      'Connected to the mesh — nearby phones can hear you';
  @override
  String get meshNotConnected => 'Not connected yet';
  @override
  String get bluetoothOff =>
      'Bluetooth is off — turn it on to reach nearby phones';

  @override
  String get language => 'Language';

  @override
  String get greeting => 'Namaskar';
  @override
  String get account => 'Account';
  @override
  String get signOut => 'Sign out';
  @override
  String get sendAlertTitle => 'Send an alert';
  @override
  String get holdSuffix => 'press and hold';
  @override
  String get lastSent => 'Last sent';
  @override
  String get alertNowSent => 'sent';
  @override
  String openCount(int n) => '$n open';
  @override
  String get sosSubtitle => 'Alert nearby phones';
  @override
  String get missingTitle => 'Missing';
  @override
  String get missingSubtitleIdle => 'Report or search';
  @override
  String missingSubtitleActive(int n) => '$n active report${n == 1 ? '' : 's'}';
  @override
  String get you => 'You';
  @override
  String get joinDifferentDindi => 'Join a different Dindi';
  @override
  String get leaveDindi => 'Leave Dindi';
  @override
  String get createOrJoinDindi => 'Create or join a Dindi';
  @override
  String get place => 'Location';
  @override
  String get time => 'Time';
  @override
  String announceQuestion(String stationName) => 'Announce $stationName?';
  @override
  String stationAvailable(String stationName) => '$stationName available';
  @override
  String stationNearby(String stationName) => '$stationName nearby';
  @override
  String get noMapsApp => 'No maps app could open on this phone';
  @override
  String get helpPointPrivacyNote =>
      'A Bluetooth broadcast is public and unencrypted - this is a location a '
      'volunteer chose to share, not a private message.';
  @override
  String alertFinished(String age) => 'Your alert from $age is finished.';
  @override
  String respondingToYours(String who) => '$who is responding to your alert.';
  @override
  String alertOutDetail(String age) =>
      'Sent $age. Nearby phones are passing it on. You will be told the '
      'moment someone responds.';

  @override
  String notifNeedsHelp(String from, String where) => '$from needs help$where';
  @override
  String notifLookFor(String name, String age, String from, String where) =>
      'Look for $name$age - reported by $from$where';
  @override
  String notifSomeoneMissing(String from, String where) =>
      '$from reported someone missing nearby$where';
  @override
  String get notifAgePrefix => 'age';
  @override
  String get notifMissingTitle => '🔎 Missing person nearby';
  @override
  String get notifSosTitle => '🆘 SOS RECEIVED';
  @override
  String notifAdvisoryTitle(String who) => '📢 Advisory from $who';
  @override
  String get notifHelpComingTitle => 'Help is coming';
  @override
  String notifHelpComingBody(String who) => '$who is responding to your alert.';
  @override
  String get notifSightingTitle => '👀 Sighting reported';
  @override
  String notifSightingBody(String who, String subject) =>
      '$who reported seeing $subject.';
  @override
  String get notifThePersonYouReported => 'the person you reported missing';

  @override
  String get wariNetwork => 'WariMesh network';
  @override
  String get networkActive => 'Network active';
  @override
  String get networkDown => 'Network down';
  @override
  String get dindisHeading => 'Dindis';
  @override
  String get participants => 'WariMesh participants';
  @override
  String get participantsCaption => 'WariMesh participants heard right now';
  @override
  String get dindiLeads => 'Dindi Leads';
  @override
  String get volunteers => 'Volunteers';
  @override
  String get warkaris => 'Warkaris';
  @override
  String get activeSos => 'Active SOS';
  @override
  String get missingWarkaris => 'Missing Warkaris';
  @override
  String get sevaPoints => 'Seva points';
  @override
  String get mukkaam => 'Mukkaam';
  @override
  String get viewDindis => 'View Dindis';
  @override
  String get noDindisHeard => 'No Dindi heard right now';
  @override
  String get noDindisHeardDetail =>
      'A Dindi appears here as soon as one of its phones is in range. '
      'This phone keeps listening.';
  @override
  String get noEmergencies => 'No active emergencies';
  @override
  String get unavailable => 'Not available';
  @override
  String get dindiCode => 'Dindi code';
  @override
  String get visibleInWariMesh => 'Visible in WariMesh now';
  @override
  String get visibleInWariMeshCaption =>
      'This counts participants this phone can hear — not the number of '
      'people in the Dindi.';
  @override
  String get leadNearby => 'Heard recently';
  @override
  String get leadLastSeen => 'Last seen';
  @override
  String get lastKnownLocation => 'Last known location';
  @override
  String get lastUpdate => 'Last update';
  @override
  String get viewDindiDetails => 'Full Dindi details';
  @override
  String get viewActiveIncidents => 'View active incidents';
  @override
  String get nearbySevaShort => 'Nearby Seva';
  @override
  String get mukkaamNoSource =>
      'Mukkaam does not travel over WariMesh. It appears only when a halt '
      'has been announced nearby.';
  @override
  String get dindiNameUnknown =>
      'Dindi names are not sent over WariMesh — only the code is visible.';
  @override
  String get participantsSingleHopNote =>
      'These counts are phones this one can hear directly, not the whole Wari.';

  @override
  String ageLabel(DateTime since) {
    final mins = DateTime.now().difference(since).inMinutes;
    if (mins < 1) return 'just now';
    if (mins < 60) return '$mins min ago';
    final hours = mins ~/ 60;
    if (hours < 24) return '${hours}h ago';
    return '${hours ~/ 24}d ago';
  }
}

/// The language picker itself.
///
/// Each language is named in its OWN script — "मराठी" and "English", never
/// "Marathi" or "इंग्रजी". Somebody who has ended up in a language they
/// cannot read has to be able to find their way out, and that only works if
/// the option they want is written the way they would recognise it.
Future<void> showLanguageSheet(BuildContext context) async {
  final chosen = await showModalBottomSheet<AppStrings>(
    context: context,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
            child: Row(
              children: [
                const Icon(Icons.translate),
                const SizedBox(width: 12),
                Text(
                  t.language,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                  ),
                ),
              ],
            ),
          ),
          for (final option in const [MarathiStrings(), EnglishStrings()])
            ListTile(
              // Generous vertical space: Devanagari sits taller than Latin,
              // and this is tapped by people with tired eyes.
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 6,
              ),
              leading: Icon(
                option.languageCode == t.languageCode
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                color: option.languageCode == t.languageCode
                    ? AppColors.relayed
                    : null,
              ),
              title: Text(
                option.languageName,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 17,
                ),
              ),
              onTap: () => Navigator.of(sheetContext).pop(option),
            ),
          const SizedBox(height: 12),
        ],
      ),
    ),
  );
  if (chosen == null) return;
  await selectLanguage(chosen);
}

/// An always-visible language toggle: both languages side by side, each in
/// its own script, no menu to open first.
///
/// This exists because the first version put the language control behind an
/// overflow menu on the Home tab, which is precisely the navigation a
/// language barrier prevents. Somebody who opens the app and cannot read it
/// has to be able to fix that from the very first screen, without guessing
/// which unlabelled icon hides the setting. So this sits on the role-select
/// screen — before anyone signs in — and as a single tap in the app bar
/// afterwards.
class LanguageToggle extends StatelessWidget {
  /// Compact drops the "भाषा / Language" caption for use inside an app bar
  /// or a tight row.
  final bool compact;

  const LanguageToggle({super.key, this.compact = false});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppStrings>(
      valueListenable: appLanguage,
      builder: (context, current, _) {
        final chips = Wrap(
          spacing: 8,
          alignment: WrapAlignment.center,
          children: [
            for (final option in const <AppStrings>[
              MarathiStrings(),
              EnglishStrings(),
            ])
              ChoiceChip(
                // Deliberately large: this is tapped by elderly people, and
                // Devanagari needs more vertical room than Latin.
                labelPadding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                label: Text(
                  option.languageName,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
                selected: option.languageCode == current.languageCode,
                onSelected: (_) => selectLanguage(option),
              ),
          ],
        );
        if (compact) return chips;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              // Both scripts in the caption too, so it is recognisable
              // whichever language the app happens to be showing.
              'भाषा / Language',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            chips,
          ],
        );
      },
    );
  }
}

/// Applies and remembers a language choice. Shared by [LanguageToggle] and
/// [showLanguageSheet] so both paths behave identically.
Future<void> selectLanguage(AppStrings chosen) async {
  if (chosen.languageCode == t.languageCode) return;
  setAppLanguage(chosen);
  try {
    await SettingsDb.set(SettingsDb.keyLanguage, chosen.languageCode);
  } catch (_) {
    // Applied for this session even if it could not be saved — the same
    // rule the Dindi and duty pickers follow.
  }
}

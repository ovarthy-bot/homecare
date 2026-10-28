/**
 * Homecare ara deposu (Google Apps Script web uygulaması).
 *
 * Uygulaması olmayan bir telefondan gelen bakım kayıtlarını bir Google Sheet'te bekletir;
 * uygulama açılınca bu kayıtları çeker. Cihaz bilgisini de burada tutar, böylece web
 * sayfası bilgiyi herkese açık bir depo yerine buradan alır.
 * Kurulum: backend/apps-script/README.md
 *
 * İki tür çağıran vardır:
 *  - Sahip (uygulama): `key` = betik özelliklerindeki SECRET. Cihaz bilgisi yükler,
 *    bekleyen kayıtları çeker ve onaylar.
 *  - Ziyaretçi (QR'ı okutan): `k` = HMAC-SHA256(SECRET, cihaz numarası)'nın ilk 16 hanesi.
 *    Yalnızca o cihazın bilgisini okuyabilir ve o cihaz için bakım kaydı bırakabilir.
 */

var SHEET_DEVICES = 'Cihazlar';
var SHEET_RECORDS = 'Kayitlar';
var DEVICE_HEADERS = ['id', 'json', 'updatedAt'];
var RECORD_HEADERS = ['recordId', 'deviceId', 'taskId', 'taskName', 'recordedAt', 'status', 'importedAt'];

// Aynı cihaz+görev için bu süre içinde gelen ikinci kayıt yok sayılır (çift dokunuş, yeniden deneme).
var DUPLICATE_WINDOW_MS = 60 * 1000;
// Sahip henüz çekmediyse en fazla bu kadar bekleyen kayıt tutulur; kötüye kullanımı sınırlar.
var MAX_PENDING = 500;
var MAX_DEVICES_PER_PUSH = 200;
var MAX_TEXT_LENGTH = 2000;
var KEY_LENGTH = 16;
var RECENT_ROWS_FOR_DUPLICATES = 200;

function doGet(e) {
  return respond_((e && e.parameter) || {});
}

function doPost(e) {
  var params;
  try {
    params = JSON.parse(e.postData.contents);
  } catch (err) {
    return json_({ ok: false, error: 'bad_request' });
  }
  return respond_(params || {});
}

function respond_(params) {
  try {
    return json_(route_(params));
  } catch (err) {
    console.error(err);
    return json_({ ok: false, error: 'server_error' });
  }
}

function json_(obj) {
  return ContentService.createTextOutput(JSON.stringify(obj)).setMimeType(ContentService.MimeType.JSON);
}

function route_(p) {
  var secret = PropertiesService.getScriptProperties().getProperty('SECRET');
  if (!secret) return { ok: false, error: 'not_configured' };

  switch (p.action) {
    case 'ping':
      return ownerOnly_(p, secret, function () { return { ok: true }; });
    case 'putDevices':
      return ownerOnly_(p, secret, putDevices_);
    case 'deleteDevice':
      return ownerOnly_(p, secret, deleteDevice_);
    case 'pull':
      return ownerOnly_(p, secret, pull_);
    case 'ack':
      return ownerOnly_(p, secret, ack_);
    case 'device':
      return visitorOnly_(p, secret, getDevice_);
    case 'record':
      return visitorOnly_(p, secret, recordTasks_);
    default:
      return { ok: false, error: 'unknown_action' };
  }
}

// --- Yetkilendirme --------------------------------------------------------------------------

function ownerOnly_(p, secret, handler) {
  if (!safeEqual_(String(p.key || ''), secret)) return { ok: false, error: 'forbidden' };
  return handler(p);
}

function visitorOnly_(p, secret, handler) {
  var id = String(p.id || '');
  if (!/^[0-9]+$/.test(id)) return { ok: false, error: 'forbidden' };
  if (!safeEqual_(String(p.k || ''), deviceKey_(secret, id))) return { ok: false, error: 'forbidden' };
  return handler(p, id);
}

/** Uygulamanın QR'a yazdığı anahtarla aynı olmalı (lib/core/services/backend_service.dart). */
function deviceKey_(secret, id) {
  return hmacHex_(secret, String(id)).substring(0, KEY_LENGTH);
}

function hmacHex_(secret, value) {
  var bytes = Utilities.computeHmacSha256Signature(value, secret);
  return bytes
    .map(function (b) { return ('0' + (b & 0xff).toString(16)).slice(-2); })
    .join('');
}

/** Süre farkından bilgi sızdırmayan karşılaştırma. */
function safeEqual_(a, b) {
  if (a.length !== b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

// --- Ziyaretçi eylemleri --------------------------------------------------------------------

function getDevice_(p, id) {
  var found = findDevice_(id);
  if (!found) return { ok: false, error: 'not_found' };
  return { ok: true, device: JSON.parse(found.json) };
}

function recordTasks_(p, id) {
  return withLock_(function () {
    var found = findDevice_(id);
    if (!found) return { ok: false, error: 'not_found' };

    var requested = Array.isArray(p.taskIds) ? p.taskIds.map(String) : [];
    if (requested.length === 0) return { ok: false, error: 'no_tasks' };

    var tasksById = {};
    (JSON.parse(found.json).tasks || []).forEach(function (t) { tasksById[String(t.id)] = t; });

    var sheet = recordsSheet_();
    var recent = readRecords_(sheet, RECENT_ROWS_FOR_DUPLICATES);
    var pending = countPending_(sheet);
    var nowMs = now_().getTime();
    var handled = {};
    var recorded = [];
    var skipped = [];

    requested.forEach(function (taskId) {
      var task = tasksById[taskId];
      if (!task) return skipped.push({ taskId: taskId, reason: 'unknown_task' });
      if (handled[taskId]) return skipped.push({ taskId: taskId, reason: 'duplicate' });
      handled[taskId] = true;

      var isDuplicate = recent.some(function (r) {
        return r.deviceId === id && r.taskId === taskId && nowMs - new Date(r.recordedAt).getTime() < DUPLICATE_WINDOW_MS;
      });
      if (isDuplicate) return skipped.push({ taskId: taskId, reason: 'duplicate' });
      if (pending >= MAX_PENDING) return skipped.push({ taskId: taskId, reason: 'queue_full' });

      sheet.appendRow([Utilities.getUuid(), id, taskId, task.name, now_().toISOString(), 'pending', '']);
      pending++;
      recorded.push({ taskId: taskId, taskName: task.name });
    });

    return { ok: true, recorded: recorded, skipped: skipped };
  });
}

// --- Sahip eylemleri ------------------------------------------------------------------------

function putDevices_(p) {
  var devices = Array.isArray(p.devices) ? p.devices : [];
  if (devices.length > MAX_DEVICES_PER_PUSH) return { ok: false, error: 'too_many_devices' };

  return withLock_(function () {
    var sheet = devicesSheet_();
    var rowById = indexById_(sheet);
    var stored = 0;

    devices.forEach(function (raw) {
      var device = sanitizeDevice_(raw);
      if (!device) return;
      var values = [String(device.id), JSON.stringify(device), now_().toISOString()];
      var row = rowById[String(device.id)];
      if (row) {
        sheet.getRange(row, 1, 1, 3).setValues([values]);
      } else {
        sheet.appendRow(values);
        rowById[String(device.id)] = sheet.getLastRow();
      }
      stored++;
    });
    return { ok: true, stored: stored };
  });
}

function deleteDevice_(p) {
  var id = String(p.id || '');
  if (!/^[0-9]+$/.test(id)) return { ok: false, error: 'bad_request' };

  return withLock_(function () {
    var row = indexById_(devicesSheet_())[id];
    if (row) devicesSheet_().deleteRow(row);
    return { ok: true, deleted: !!row };
  });
}

function pull_() {
  var records = readRecords_(recordsSheet_(), 0)
    .filter(function (r) { return r.status === 'pending'; })
    .map(function (r) {
      return {
        recordId: r.recordId,
        deviceId: Number(r.deviceId),
        taskId: Number(r.taskId),
        taskName: r.taskName,
        recordedAt: r.recordedAt,
      };
    });
  return { ok: true, records: records };
}

function ack_(p) {
  var ids = Array.isArray(p.ids) ? p.ids.map(String) : [];
  return withLock_(function () {
    var sheet = recordsSheet_();
    var rows = sheet.getLastRow() > 1 ? sheet.getRange(2, 1, sheet.getLastRow() - 1, 1).getValues() : [];
    var wanted = {};
    ids.forEach(function (id) { wanted[id] = true; });

    var acknowledged = 0;
    var stamp = now_().toISOString();
    rows.forEach(function (row, i) {
      if (!wanted[String(row[0])]) return;
      sheet.getRange(i + 2, 6, 1, 2).setValues([['imported', stamp]]);
      acknowledged++;
    });
    return { ok: true, acknowledged: acknowledged };
  });
}

// --- Cihaz verisi ---------------------------------------------------------------------------

/** Yalnızca bilinen alanları ve sınırlı uzunlukta metni saklar. */
function sanitizeDevice_(raw) {
  if (!raw || !/^[0-9]+$/.test(String(raw.id))) return null;

  var device = { id: Number(raw.id), name: text_(raw.name), room: text_(raw.room) };
  ['category', 'purchaseDate', 'serviceInfo', 'notes'].forEach(function (field) {
    if (raw[field]) device[field] = text_(raw[field]);
  });
  if (raw.warranty !== undefined && !isNaN(Number(raw.warranty))) device.warranty = Number(raw.warranty);

  device.tasks = (Array.isArray(raw.tasks) ? raw.tasks : [])
    .filter(function (t) { return t && /^[0-9]+$/.test(String(t.id)); })
    .map(function (t) {
      var task = { id: Number(t.id), name: text_(t.name), intervalDays: Number(t.intervalDays) || 30 };
      if (t.lastCompletedAt) task.lastCompletedAt = text_(t.lastCompletedAt);
      return task;
    });
  return device;
}

function text_(value) {
  return String(value === undefined || value === null ? '' : value).substring(0, MAX_TEXT_LENGTH);
}

function findDevice_(id) {
  var sheet = devicesSheet_();
  var row = indexById_(sheet)[String(id)];
  if (!row) return null;
  return { row: row, json: String(sheet.getRange(row, 2).getValues()[0][0]) };
}

/** id -> satır numarası. */
function indexById_(sheet) {
  var map = {};
  var last = sheet.getLastRow();
  if (last < 2) return map;
  sheet.getRange(2, 1, last - 1, 1).getValues().forEach(function (row, i) {
    map[String(row[0])] = i + 2;
  });
  return map;
}

// --- Kayıtlar -------------------------------------------------------------------------------

/** En fazla `limit` son satırı nesne olarak okur; 0 hepsi demektir. */
function readRecords_(sheet, limit) {
  var last = sheet.getLastRow();
  if (last < 2) return [];
  var first = limit > 0 ? Math.max(2, last - limit + 1) : 2;
  return sheet
    .getRange(first, 1, last - first + 1, RECORD_HEADERS.length)
    .getValues()
    .map(function (row) {
      return {
        recordId: String(row[0]),
        deviceId: String(row[1]),
        taskId: String(row[2]),
        taskName: String(row[3]),
        recordedAt: String(row[4]),
        status: String(row[5]),
      };
    });
}

function countPending_(sheet) {
  return readRecords_(sheet, 0).filter(function (r) { return r.status === 'pending'; }).length;
}

// --- Sayfalar ve yardımcılar ----------------------------------------------------------------

function devicesSheet_() {
  return sheet_(SHEET_DEVICES, DEVICE_HEADERS);
}

function recordsSheet_() {
  return sheet_(SHEET_RECORDS, RECORD_HEADERS);
}

/** Sayfayı yoksa başlık satırıyla oluşturur. Tüm hücreler metin: Sheets tarih/sayı çevirmesin. */
function sheet_(name, headers) {
  var spreadsheet = SpreadsheetApp.getActiveSpreadsheet();
  var sheet = spreadsheet.getSheetByName(name);
  if (sheet) return sheet;

  sheet = spreadsheet.insertSheet(name);
  sheet.getRange(1, 1, sheet.getMaxRows(), headers.length).setNumberFormat('@');
  sheet.getRange(1, 1, 1, headers.length).setValues([headers]);
  sheet.setFrozenRows(1);
  return sheet;
}

function withLock_(work) {
  var lock = LockService.getScriptLock();
  lock.waitLock(15000);
  try {
    return work();
  } finally {
    lock.releaseLock();
  }
}

function now_() {
  return new Date();
}

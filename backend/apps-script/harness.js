// Code.gs'i Google'ın servislerini bellekte taklit ederek Node'da çalıştırır.
// Hem testler (Code.test.js) hem de web sayfasını yerelde denemek (serve.js) kullanır.
const crypto = require('node:crypto');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

class MockSheet {
  constructor() {
    this.rows = []; // rows[0] = 1. satır
  }

  getLastRow() {
    return this.rows.length;
  }

  getMaxRows() {
    return 1000;
  }

  appendRow(values) {
    this.rows.push(values.slice());
  }

  deleteRow(row) {
    this.rows.splice(row - 1, 1);
  }

  setFrozenRows() {}

  getRange(row, col, numRows = 1, numCols = 1) {
    const sheet = this;
    return {
      getValues() {
        return Array.from({ length: numRows }, (_, r) =>
          Array.from({ length: numCols }, (_, c) => (sheet.rows[row - 1 + r] || [])[col - 1 + c] ?? ''),
        );
      },
      setValues(values) {
        values.forEach((line, r) => {
          sheet.rows[row - 1 + r] = sheet.rows[row - 1 + r] || [];
          line.forEach((value, c) => {
            sheet.rows[row - 1 + r][col - 1 + c] = value;
          });
        });
      },
      setValue(value) {
        this.setValues([[value]]);
      },
      setNumberFormat() {
        return this;
      },
    };
  }
}

/** @param {{secret?: string|null}} options */
function createBackend({ secret = 'secret' } = {}) {
  const sheets = new Map();
  const properties = secret === null ? {} : { SECRET: secret };
  let current = new Date();

  const sandbox = {
    console,
    SpreadsheetApp: {
      getActiveSpreadsheet: () => ({
        getSheetByName: (name) => sheets.get(name) || null,
        insertSheet: (name) => {
          const sheet = new MockSheet();
          sheets.set(name, sheet);
          return sheet;
        },
      }),
    },
    PropertiesService: { getScriptProperties: () => ({ getProperty: (key) => properties[key] ?? null }) },
    LockService: { getScriptLock: () => ({ waitLock() {}, releaseLock() {} }) },
    Utilities: {
      getUuid: () => crypto.randomUUID(),
      // Apps Script işaretli bayt dizisi (-128..127) döndürür.
      computeHmacSha256Signature: (value, key) =>
        Array.from(crypto.createHmac('sha256', key).update(value).digest()).map((b) => (b > 127 ? b - 256 : b)),
    },
    ContentService: {
      MimeType: { JSON: 'application/json' },
      createTextOutput: (text) => ({ text, setMimeType() { return this; } }),
    },
  };

  const context = vm.createContext(sandbox);
  vm.runInContext(fs.readFileSync(path.join(__dirname, 'Code.gs'), 'utf8'), context);
  context.now_ = () => new Date(current);

  const parse = (output) => JSON.parse(output.text);
  return {
    context,
    sheets,
    /** Saati ileri alır (tekrar koruma penceresi testleri için). */
    advance(ms) {
      current = new Date(current.getTime() + ms);
    },
    get(params) {
      return parse(context.doGet({ parameter: params }));
    },
    post(body) {
      return parse(context.doPost({ postData: { contents: typeof body === 'string' ? body : JSON.stringify(body) } }));
    },
  };
}

module.exports = { createBackend };

// Çalıştırmak için: node --test backend/apps-script/Code.test.js
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const { beforeEach, describe, it } = require('node:test');

const { createBackend } = require('./harness');

const SECRET = 'secret';
const keyFor = (id) => crypto.createHmac('sha256', SECRET).update(String(id)).digest('hex').substring(0, 16);

const coffeeMachine = {
  id: 3,
  name: 'Philips Kahve Makinesi',
  room: 'Mutfak',
  category: 'Mutfak Aletleri',
  warranty: 24,
  tasks: [
    { id: 11, name: 'Kireç çözme', intervalDays: 60, lastCompletedAt: '2026-09-01T10:00:00.000Z' },
    { id: 12, name: 'Çöp haznesi temizliği', intervalDays: 7 },
  ],
};

describe('Code.gs', () => {
  let backend;
  const owner = (extra) => ({ key: SECRET, ...extra });
  const visitor = (id, extra) => ({ id, k: keyFor(id), ...extra });

  beforeEach(() => {
    backend = createBackend({ secret: SECRET });
    assert.equal(backend.post(owner({ action: 'putDevices', devices: [coffeeMachine] })).ok, true);
  });

  describe('anahtarlar', () => {
    it('cihaz anahtarı Dart tarafıyla aynı test vektörünü üretir', () => {
      // lib/core/services/backend_service.dart testindeki değerin aynısı:
      // HMAC-SHA256("secret", "3") = 88a43b1b8ef6d2e900797363da21fd2bb29351d3022389feb31fb1340a94dae2
      assert.equal(backend.context.deviceKey_('secret', '3'), '88a43b1b8ef6d2e9');
    });

    it('SECRET tanımlı değilse hiçbir şey çalışmaz', () => {
      const unconfigured = createBackend({ secret: null });
      assert.deepEqual(unconfigured.get({ action: 'ping', key: 'x' }), { ok: false, error: 'not_configured' });
    });

    it('bozuk JSON govdesi bad_request döner', () => {
      assert.deepEqual(backend.post('{bozuk'), { ok: false, error: 'bad_request' });
    });

    it('bilinmeyen eylem reddedilir', () => {
      assert.deepEqual(backend.get({ action: 'sil' }), { ok: false, error: 'unknown_action' });
    });
  });

  describe('sahip eylemleri', () => {
    it('doğru anahtarla ping başarılı, yanlışla reddedilir', () => {
      assert.deepEqual(backend.get(owner({ action: 'ping' })), { ok: true });
      assert.deepEqual(backend.get({ action: 'ping', key: 'yanlis' }), { ok: false, error: 'forbidden' });
      assert.deepEqual(backend.get({ action: 'ping' }), { ok: false, error: 'forbidden' });
    });

    it('ziyaretçi anahtarı sahip eylemlerini açmaz', () => {
      for (const action of ['ping', 'pull', 'ack', 'putDevices', 'deleteDevice']) {
        const response = backend.post({ action, key: keyFor(3), k: keyFor(3), id: 3, ids: [], devices: [] });
        assert.deepEqual(response, { ok: false, error: 'forbidden' }, action);
      }
    });

    it('cihaz güncellenir (ikinci kez ekleme yerine)', () => {
      backend.post(owner({ action: 'putDevices', devices: [{ ...coffeeMachine, name: 'Yeni Ad' }] }));

      assert.equal(backend.get({ action: 'device', ...visitor(3) }).device.name, 'Yeni Ad');
      assert.equal(backend.sheets.get('Cihazlar').getLastRow(), 2, 'başlık + tek cihaz');
    });

    it('bilinmeyen alanları atar, uzun metni kırpar, geçersiz cihazı yok sayar', () => {
      const response = backend.post(
        owner({
          action: 'putDevices',
          devices: [
            { id: 7, name: 'A'.repeat(5000), room: 'x', tasks: [{ id: 1, name: 't', intervalDays: 'abc', evil: 1 }], hack: 'x' },
            { id: 'abc', name: 'geçersiz' },
            null,
          ],
        }),
      );
      assert.equal(response.stored, 1);

      const device = backend.get({ action: 'device', ...visitor(7) }).device;
      assert.equal(device.name.length, 2000);
      assert.equal('hack' in device, false);
      assert.deepEqual(device.tasks, [{ id: 1, name: 't', intervalDays: 30 }]);
    });

    it('çok fazla cihaz tek seferde kabul edilmez', () => {
      const devices = Array.from({ length: 201 }, (_, i) => ({ id: i + 100, name: 'x', room: 'y' }));
      assert.deepEqual(backend.post(owner({ action: 'putDevices', devices })), { ok: false, error: 'too_many_devices' });
    });

    it('cihaz silinir', () => {
      assert.deepEqual(backend.post(owner({ action: 'deleteDevice', id: 3 })), { ok: true, deleted: true });
      assert.deepEqual(backend.get({ action: 'device', ...visitor(3) }), { ok: false, error: 'not_found' });
      assert.deepEqual(backend.post(owner({ action: 'deleteDevice', id: 3 })), { ok: true, deleted: false });
      assert.deepEqual(backend.post(owner({ action: 'deleteDevice', id: 'x' })), { ok: false, error: 'bad_request' });
    });
  });

  describe('ziyaretçi: cihaz bilgisi', () => {
    it('doğru anahtarla cihaz bilgisi gelir', () => {
      const response = backend.get({ action: 'device', ...visitor(3) });

      assert.equal(response.ok, true);
      assert.equal(response.device.name, 'Philips Kahve Makinesi');
      assert.deepEqual(
        response.device.tasks.map((t) => t.id),
        [11, 12],
      );
    });

    it('başka cihazın anahtarı, yanlış anahtar ve geçersiz numara reddedilir', () => {
      const forbidden = { ok: false, error: 'forbidden' };
      assert.deepEqual(backend.get({ action: 'device', id: 3, k: keyFor(4) }), forbidden);
      assert.deepEqual(backend.get({ action: 'device', id: 3, k: 'yanlis' }), forbidden);
      assert.deepEqual(backend.get({ action: 'device', id: 3 }), forbidden);
      assert.deepEqual(backend.get({ action: 'device', id: '3 ', k: keyFor(3) }), forbidden);
      assert.deepEqual(backend.get({ action: 'device', id: '../3', k: keyFor(3) }), forbidden);
    });

    it('anahtarı doğru ama kayıtlı olmayan cihaz için not_found döner', () => {
      assert.deepEqual(backend.get({ action: 'device', ...visitor(99) }), { ok: false, error: 'not_found' });
    });
  });

  describe('ziyaretçi: bakım kaydı', () => {
    it('seçilen görevler kaydedilir ve sahip çekince görür', () => {
      const response = backend.post({ action: 'record', ...visitor(3, { taskIds: [11, 12] }) });

      assert.equal(response.ok, true);
      assert.deepEqual(
        response.recorded.map((r) => r.taskName),
        ['Kireç çözme', 'Çöp haznesi temizliği'],
      );

      const { records } = backend.get(owner({ action: 'pull' }));
      assert.equal(records.length, 2);
      assert.deepEqual(
        records.map((r) => [r.deviceId, r.taskId, r.taskName]),
        [
          [3, 11, 'Kireç çözme'],
          [3, 12, 'Çöp haznesi temizliği'],
        ],
      );
      assert.ok(records.every((r) => r.recordId && !Number.isNaN(Date.parse(r.recordedAt))));
    });

    it('kayıt zamanı sunucu saatidir, istemcinin gönderdiği değer kullanılmaz', () => {
      backend.post({ action: 'record', ...visitor(3, { taskIds: [11], recordedAt: '1999-01-01T00:00:00.000Z' }) });

      const { records } = backend.get(owner({ action: 'pull' }));
      assert.ok(Date.parse(records[0].recordedAt) > Date.parse('2020-01-01'));
    });

    it('göreve ait olmayan numara atlanır, diğerleri kaydedilir', () => {
      const response = backend.post({ action: 'record', ...visitor(3, { taskIds: [11, 999] }) });

      assert.deepEqual(response.recorded.map((r) => r.taskId), ['11']);
      assert.deepEqual(response.skipped, [{ taskId: '999', reason: 'unknown_task' }]);
    });

    it('görev seçilmediyse reddedilir', () => {
      assert.deepEqual(backend.post({ action: 'record', ...visitor(3, { taskIds: [] }) }), { ok: false, error: 'no_tasks' });
      assert.deepEqual(backend.post({ action: 'record', ...visitor(3) }), { ok: false, error: 'no_tasks' });
    });

    it('bir cihazın anahtarıyla başka cihaza kayıt bırakılamaz', () => {
      backend.post(owner({ action: 'putDevices', devices: [{ id: 4, name: 'Klima', room: 'Salon', tasks: [{ id: 41, name: 'Filtre', intervalDays: 30 }] }] }));

      const response = backend.post({ action: 'record', id: 4, k: keyFor(3), taskIds: [41] });

      assert.deepEqual(response, { ok: false, error: 'forbidden' });
      assert.equal(backend.get(owner({ action: 'pull' })).records.length, 0);
    });

    it('bilinmeyen cihaza kayıt bırakılamaz', () => {
      assert.deepEqual(backend.post({ action: 'record', ...visitor(99, { taskIds: [1] }) }), { ok: false, error: 'not_found' });
    });

    it('aynı görevin 60 sn içinde tekrar kaydı yok sayılır, sonrasında kabul edilir', () => {
      backend.post({ action: 'record', ...visitor(3, { taskIds: [11] }) });

      const again = backend.post({ action: 'record', ...visitor(3, { taskIds: [11] }) });
      assert.deepEqual(again.recorded, []);
      assert.deepEqual(again.skipped, [{ taskId: '11', reason: 'duplicate' }]);

      backend.advance(61 * 1000);
      assert.equal(backend.post({ action: 'record', ...visitor(3, { taskIds: [11] }) }).recorded.length, 1);
      assert.equal(backend.get(owner({ action: 'pull' })).records.length, 2);
    });

    it('aynı istekte tekrarlanan görev bir kez kaydedilir', () => {
      const response = backend.post({ action: 'record', ...visitor(3, { taskIds: [11, 11] }) });

      assert.equal(response.recorded.length, 1);
      assert.deepEqual(response.skipped, [{ taskId: '11', reason: 'duplicate' }]);
    });

    it('bekleyen kayıt sınırı dolunca yenisi kabul edilmez', () => {
      backend.context.MAX_PENDING = 1;

      const response = backend.post({ action: 'record', ...visitor(3, { taskIds: [11, 12] }) });

      assert.equal(response.recorded.length, 1);
      assert.deepEqual(response.skipped, [{ taskId: '12', reason: 'queue_full' }]);
    });
  });

  describe('çekme ve onaylama', () => {
    it('onaylanan kayıtlar bir daha gelmez, onaylanmayanlar kalır', () => {
      backend.post({ action: 'record', ...visitor(3, { taskIds: [11, 12] }) });
      const [first, second] = backend.get(owner({ action: 'pull' })).records;

      const ack = backend.post(owner({ action: 'ack', ids: [first.recordId, 'olmayan-kayit'] }));

      assert.deepEqual(ack, { ok: true, acknowledged: 1 });
      assert.deepEqual(
        backend.get(owner({ action: 'pull' })).records.map((r) => r.recordId),
        [second.recordId],
      );
    });

    it('onaylanmış kayıt satırı silinmez, durumu imported olur', () => {
      backend.post({ action: 'record', ...visitor(3, { taskIds: [11] }) });
      const { records } = backend.get(owner({ action: 'pull' }));
      backend.post(owner({ action: 'ack', ids: [records[0].recordId] }));

      const row = backend.sheets.get('Kayitlar').rows[1];
      assert.equal(row[5], 'imported');
      assert.ok(row[6]);
    });

    it('kayıt yoksa boş liste döner', () => {
      assert.deepEqual(backend.get(owner({ action: 'pull' })), { ok: true, records: [] });
    });
  });
});

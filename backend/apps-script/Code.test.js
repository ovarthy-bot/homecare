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

    it('model ve fiyatı saklar; geçersiz fiyatı atar', () => {
      backend.post(
        owner({
          action: 'putDevices',
          devices: [
            { id: 7, name: 'Yazıcı', room: 'x', modelInfo: 'Epson EcoTank L3250', price: 8489.5 },
            { id: 8, name: 'Fiyatsız', room: 'x', modelInfo: '', price: -5 },
            { id: 9, name: 'Metin fiyat', room: 'x', price: 'pahalı' },
          ],
        }),
      );

      const priced = backend.get({ action: 'device', ...visitor(7) }).device;
      assert.equal(priced.modelInfo, 'Epson EcoTank L3250');
      assert.equal(priced.price, 8489.5);

      const unpriced = backend.get({ action: 'device', ...visitor(8) }).device;
      assert.equal('price' in unpriced, false);
      assert.equal('modelInfo' in unpriced, false, 'boş model saklanmaz');
      assert.equal('price' in backend.get({ action: 'device', ...visitor(9) }).device, false);
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

  describe('ziyaretçi: bekleyen kayıtlar cihaz bilgisine yansır', () => {
    const lastDone = (response, taskId) => response.device.tasks.find((t) => t.id === taskId).lastCompletedAt;
    const pulledAt = (taskId) => backend.get(owner({ action: 'pull' })).records.filter((r) => r.taskId === taskId).map((r) => r.recordedAt);

    it('kayıt bırakılınca görevin bakım tarihi telefon almadan da hemen güncellenir', () => {
      const before = backend.get({ action: 'device', ...visitor(3) });
      assert.equal(lastDone(before, 11), '2026-09-01T10:00:00.000Z');
      assert.equal(lastDone(before, 12), undefined);

      backend.post({ action: 'record', ...visitor(3, { taskIds: [11, 12] }) });

      const after = backend.get({ action: 'device', ...visitor(3) });
      assert.equal(lastDone(after, 11), pulledAt(11)[0]);
      assert.equal(lastDone(after, 12), pulledAt(12)[0]);
    });

    it('yalnızca kayıt bırakılan görev değişir', () => {
      backend.post({ action: 'record', ...visitor(3, { taskIds: [12] }) });

      const after = backend.get({ action: 'device', ...visitor(3) });
      assert.equal(lastDone(after, 11), '2026-09-01T10:00:00.000Z');
      assert.equal(lastDone(after, 12), pulledAt(12)[0]);
    });

    it('aynı görev için birden çok bekleyen kayıt varsa en yenisi görünür', () => {
      backend.post({ action: 'record', ...visitor(3, { taskIds: [11] }) });
      backend.advance(61 * 1000);
      backend.post({ action: 'record', ...visitor(3, { taskIds: [11] }) });

      const [first, second] = pulledAt(11);
      assert.ok(Date.parse(second) > Date.parse(first));
      assert.equal(lastDone(backend.get({ action: 'device', ...visitor(3) }), 11), second);
    });

    it('depolanan tarih bekleyen kayıttan yeniyse depolanan korunur', () => {
      backend.post(owner({ action: 'putDevices', devices: [{ ...coffeeMachine, tasks: [{ id: 11, name: 'Kireç çözme', intervalDays: 60, lastCompletedAt: '2999-01-01T00:00:00.000Z' }] }] }));
      backend.post({ action: 'record', ...visitor(3, { taskIds: [11] }) });

      assert.equal(lastDone(backend.get({ action: 'device', ...visitor(3) }), 11), '2999-01-01T00:00:00.000Z');
    });

    it('telefon kaydı alıp tarihi gönderince telefonun değeri geçerli olur, geri alma da yansır', () => {
      backend.post({ action: 'record', ...visitor(3, { taskIds: [11] }) });
      const [recordedAt] = pulledAt(11);
      const record = backend.get(owner({ action: 'pull' })).records[0];
      backend.post(owner({ action: 'ack', ids: [record.recordId] }));

      // Telefon aldıktan sonra güncel tarihi gönderir.
      backend.post(owner({ action: 'putDevices', devices: [{ ...coffeeMachine, tasks: [{ id: 11, name: 'Kireç çözme', intervalDays: 60, lastCompletedAt: recordedAt }, coffeeMachine.tasks[1]] }] }));
      assert.equal(lastDone(backend.get({ action: 'device', ...visitor(3) }), 11), recordedAt);

      // Telefonda geri alınırsa eski tarih gönderilir ve bekleyen kayıt kalmadığı için o geçerli olur.
      backend.post(owner({ action: 'putDevices', devices: [coffeeMachine] }));
      assert.equal(lastDone(backend.get({ action: 'device', ...visitor(3) }), 11), '2026-09-01T10:00:00.000Z');
    });

    it('başka cihazın bekleyen kaydı bu cihaza karışmaz', () => {
      backend.post(owner({ action: 'putDevices', devices: [{ id: 4, name: 'Klima', room: 'Salon', tasks: [{ id: 11, name: 'Aynı numaralı görev', intervalDays: 30 }] }] }));
      backend.post({ action: 'record', ...visitor(3, { taskIds: [11] }) });

      assert.equal(lastDone(backend.get({ action: 'device', ...visitor(4) }), 11), undefined);
    });
  });

  describe('web notu', () => {
    const noteOf = (id, text) => backend.post({ action: 'note', ...visitor(id, { text }) });

    it('not kaydedilir, sayfa yenilenince ve sahip çekince görünür', () => {
      assert.deepEqual(noteOf(3, '  Filtre: F-12  '), { ok: true, notes: 'Filtre: F-12' });

      assert.equal(backend.get({ action: 'device', ...visitor(3) }).device.notes, 'Filtre: F-12');
      const { notes } = backend.get(owner({ action: 'pull' }));
      assert.equal(notes.length, 1);
      assert.equal(notes[0].deviceId, 3);
      assert.equal(notes[0].text, 'Filtre: F-12');
      assert.ok(notes[0].noteId && notes[0].editedAt);
    });

    it('aynı cihazın ikinci notu birincinin yerine geçer ve yeni numara alır', () => {
      noteOf(3, 'birinci');
      const first = backend.get(owner({ action: 'pull' })).notes[0];
      noteOf(3, 'ikinci');

      const { notes } = backend.get(owner({ action: 'pull' }));
      assert.equal(notes.length, 1);
      assert.equal(notes[0].text, 'ikinci');
      assert.notEqual(notes[0].noteId, first.noteId);
    });

    it('notu silmek (boş metin) cihazın notunu kaldırır', () => {
      backend.post(owner({ action: 'putDevices', devices: [{ ...coffeeMachine, notes: 'eski not' }] }));
      assert.equal(backend.get({ action: 'device', ...visitor(3) }).device.notes, 'eski not');

      noteOf(3, '   ');

      assert.equal('notes' in backend.get({ action: 'device', ...visitor(3) }).device, false);
      assert.equal(backend.get(owner({ action: 'pull' })).notes[0].text, '');
    });

    it('bekleyen not saklanan cihaz notunun önüne geçer; telefon onaylayıp gönderince onun değeri geçerli olur', () => {
      backend.post(owner({ action: 'putDevices', devices: [{ ...coffeeMachine, notes: 'telefondaki' }] }));
      noteOf(3, 'webdeki');
      assert.equal(backend.get({ action: 'device', ...visitor(3) }).device.notes, 'webdeki');

      const [note] = backend.get(owner({ action: 'pull' })).notes;
      backend.post(owner({ action: 'ack', noteIds: [note.noteId] }));
      backend.post(owner({ action: 'putDevices', devices: [{ ...coffeeMachine, notes: 'webdeki, telefonda düzeltildi' }] }));

      assert.equal(backend.get({ action: 'device', ...visitor(3) }).device.notes, 'webdeki, telefonda düzeltildi');
    });

    it('onaylanan not bir daha gelmez; onay beklerken yazılan yeni not onaydan etkilenmez', () => {
      noteOf(3, 'birinci');
      const [first] = backend.get(owner({ action: 'pull' })).notes;
      noteOf(3, 'ikinci'); // telefon birinciyi çekmiş ama henüz onaylamamış

      const ack = backend.post(owner({ action: 'ack', noteIds: [first.noteId] }));

      assert.deepEqual(ack, { ok: true, acknowledged: 0, notesAcknowledged: 0 });
      const [second] = backend.get(owner({ action: 'pull' })).notes;
      assert.equal(second.text, 'ikinci');

      assert.equal(backend.post(owner({ action: 'ack', noteIds: [second.noteId] })).notesAcknowledged, 1);
      assert.deepEqual(backend.get(owner({ action: 'pull' })).notes, []);
    });

    it('başka cihazın anahtarıyla, yanlış anahtarla ve bilinmeyen cihaza not yazılamaz', () => {
      assert.deepEqual(backend.post({ action: 'note', id: 3, k: keyFor(4), text: 'x' }), { ok: false, error: 'forbidden' });
      assert.deepEqual(backend.post({ action: 'note', id: 3, k: 'yanlis', text: 'x' }), { ok: false, error: 'forbidden' });
      assert.deepEqual(noteOf(99, 'x'), { ok: false, error: 'not_found' });
      assert.deepEqual(backend.get(owner({ action: 'pull' })).notes, []);
    });

    it('metin olmayan ya da çok uzun not reddedilir', () => {
      assert.deepEqual(noteOf(3, 42), { ok: false, error: 'bad_request' });
      assert.deepEqual(noteOf(3, undefined), { ok: false, error: 'bad_request' });
      assert.deepEqual(noteOf(3, 'a'.repeat(2001)), { ok: false, error: 'too_long' });
      assert.equal(noteOf(3, 'a'.repeat(2000)).ok, true);
    });

    it('formül gibi görünen not Sheet e metin olarak yazılır', () => {
      noteOf(3, '=IMPORTXML("https://kotu.example","//a")');

      const cell = backend.sheets.get('Notlar').rows[1][2];
      assert.ok(cell.startsWith('"'), 'JSON olarak saklanır, "=" ile başlamaz');
      assert.equal(backend.get(owner({ action: 'pull' })).notes[0].text, '=IMPORTXML("https://kotu.example","//a")');
    });

    it('sahip eylemleri ziyaretçi anahtarıyla çalışmaz: not çekme ve onay', () => {
      noteOf(3, 'x');
      assert.deepEqual(backend.get({ action: 'pull', key: keyFor(3) }), { ok: false, error: 'forbidden' });
      assert.deepEqual(backend.post({ action: 'ack', key: keyFor(3), noteIds: ['x'] }), { ok: false, error: 'forbidden' });
    });

    it('cihaz silinince bekleyen notu da silinir', () => {
      noteOf(3, 'x');
      backend.post(owner({ action: 'deleteDevice', id: 3 }));

      assert.deepEqual(backend.get(owner({ action: 'pull' })).notes, []);
    });
  });

  describe('cihaz resmi', () => {
    const jpeg = 'data:image/jpeg;base64,/9j/4AAQSkZJRgABAQEASABIAAD/2wBD==';
    const push = (device) => backend.post(owner({ action: 'putDevices', devices: [device] }));
    const withStamp = (stamp) => ({ ...coffeeMachine, imageStamp: stamp });
    const putImage = (extra) => backend.post(owner({ action: 'putImage', id: 3, image: jpeg, stamp: 's1', ...extra }));

    it('fotoğrafı olan cihaz için resim istenir; yüklenince sayfa resmi görür', () => {
      assert.deepEqual(push(withStamp('s1')).needImage, [3]);
      assert.equal('image' in backend.get({ action: 'device', ...visitor(3) }).device, false);

      assert.deepEqual(putImage(), { ok: true });

      assert.equal(backend.get({ action: 'device', ...visitor(3) }).device.image, jpeg);
    });

    it('damga değişmediyse resim yeniden istenmez, değiştiyse istenir', () => {
      push(withStamp('s1'));
      putImage();

      assert.deepEqual(push(withStamp('s1')).needImage, []);
      assert.deepEqual(push(withStamp('s2')).needImage, [3]);
    });

    it('resim yenilenince satır çoğalmaz', () => {
      push(withStamp('s1'));
      putImage();
      putImage({ stamp: 's2', image: 'data:image/jpeg;base64,AAAA' });

      assert.equal(backend.sheets.get('Resimler').getLastRow(), 2, 'başlık + tek resim');
      assert.equal(backend.get({ action: 'device', ...visitor(3) }).device.image, 'data:image/jpeg;base64,AAAA');
    });

    it('fotoğraf kaldırılınca (damga yok) saklanan resim silinir', () => {
      push(withStamp('s1'));
      putImage();

      assert.deepEqual(push(coffeeMachine).needImage, []);

      assert.equal('image' in backend.get({ action: 'device', ...visitor(3) }).device, false);
      assert.equal(backend.sheets.get('Resimler').getLastRow(), 1);
    });

    it('resmi olmayan cihazlar ve damgasız gönderim resme dokunmaz', () => {
      push(withStamp('s1'));
      putImage();
      backend.post(owner({ action: 'putDevices', devices: [{ id: 4, name: 'Başka', room: 'x' }] }));

      assert.equal(backend.get({ action: 'device', ...visitor(3) }).device.image, jpeg);
    });

    it('resim yalnızca sahip anahtarıyla yüklenir', () => {
      push(withStamp('s1'));
      const visitorAttempt = backend.post({ action: 'putImage', ...visitor(3, { image: jpeg }), key: keyFor(3) });

      assert.deepEqual(visitorAttempt, { ok: false, error: 'forbidden' });
      assert.equal(backend.post({ action: 'putImage', id: 3, image: jpeg }).error, 'forbidden');
    });

    it('JPEG olmayan, bozuk ya da çok büyük resim ve bilinmeyen cihaz reddedilir', () => {
      push(withStamp('s1'));

      assert.equal(putImage({ image: 'data:image/png;base64,AAAA' }).error, 'bad_request');
      assert.equal(putImage({ image: 'https://kotu.example/x.jpg' }).error, 'bad_request');
      assert.equal(putImage({ image: 'data:image/jpeg;base64,AA"><script>' }).error, 'bad_request');
      assert.equal(putImage({ image: 42 }).error, 'bad_request');
      assert.equal(putImage({ id: 'abc' }).error, 'bad_request');
      assert.equal(putImage({ image: `data:image/jpeg;base64,${'A'.repeat(45000)}` }).error, 'too_large');
      assert.equal(putImage({ id: 99 }).error, 'not_found');
      assert.equal(backend.sheets.get('Resimler').getLastRow(), 1, 'hiçbiri yazılmadı');
    });

    it('cihaz silinince resmi de silinir', () => {
      push(withStamp('s1'));
      putImage();

      backend.post(owner({ action: 'deleteDevice', id: 3 }));

      assert.equal(backend.sheets.get('Resimler').getLastRow(), 1);
    });
  });

  describe('çekme ve onaylama', () => {
    it('onaylanan kayıtlar bir daha gelmez, onaylanmayanlar kalır', () => {
      backend.post({ action: 'record', ...visitor(3, { taskIds: [11, 12] }) });
      const [first, second] = backend.get(owner({ action: 'pull' })).records;

      const ack = backend.post(owner({ action: 'ack', ids: [first.recordId, 'olmayan-kayit'] }));

      assert.deepEqual(ack, { ok: true, acknowledged: 1, notesAcknowledged: 0 });
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
      assert.deepEqual(backend.get(owner({ action: 'pull' })), { ok: true, records: [], notes: [] });
    });
  });
});

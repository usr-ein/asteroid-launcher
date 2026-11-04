/*
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * The levels that the waveform's mapping is tuned and tested against
 * (VoiceNoteView's barHeight and the floor under it, src/qml/compositor/
 * voicenoteview.js). One character per 50 ms, in the mockup's encoding:
 * dBFS = the character's code - 125, so "A" is -60 and "i" is -20. Each is the
 * RMS of 50 ms at the capture's +20 dB gain.
 *
 * - SPEECH: the speech and room note, the main repo's docs/prd/voice_notes_mockup.html
 *   LEVELS, 836 levels: the synthetic note scaled to the sample peak of speech
 *   close to the microphone (-23 to -27 dBFS, sound/README.md) and mixed with
 *   the room. 50 ms RMS: p10 -47, median -39, p90 -34, max -29.
 * - ROOM_BUSY: a busier room, with something going on in the background, the
 *   capture of 2026-11-03 18:05, 298 levels. Min -57, p10 -52, median -43,
 *   p90 -35, max -29. Ten of its characters are the backslash (value -33 dBFS),
 *   which a JavaScript string writes as two.
 * - ROOM_QUIET: a synthetic quiet room, about -52 +/- 3 dBFS (normal, rounded,
 *   between -58 and -40), 600 levels, from a fixed seed.
 * - NOTE_2230: the user's own note of 2026-11-03 22:30, 519 levels (26 s), the
 *   levels only, as the main repo's voice notes work computed them. A tick at
 *   0.5 s, speech to 11.0 s (per-second medians -30 to -37 dBFS, peaks -24 to
 *   -26, the gaps between words down to -45 to -50), the quiet room from 11.0 to
 *   15.5 s the user recorded for the tuning (about -60 to -62 dBFS, peaks at
 *   or below -55; the encoding's clamp at -60 hides that it is really -61 to
 *   -67), then speech again to the end. p10 -61.5, median -42, p90 -29, max -24.
 *   Seventeen of its characters are the backslash.
 * - ROOM_QUIET_SKEWED: a synthetic quiet room shaped like the capture of
 *   2026-11-03 19:56 (min -54.7, median -49.7, max -39.2 dBFS): -54.7 plus a
 *   gamma(3, 1.7), rounded, 600 levels, from a fixed seed. Its tail is heavy.
 * - LIVE_0010: a hold of 4 s on the watch, 2026-11-04 00:10:09, as the
 *   launcher's VoiceNotes got it: each Levels signal of ioslink, `at` ms after
 *   the press (State's startedAt) that it came, `from` its fromMs and `cb` its
 *   centibels, as busctl monitor recorded them (note 625524EF, 0:03, saved).
 *   The display was off at the press; Keep came at 518 ms and Stop at 4042.
 *   The capture's first level starts 129 ms after the press, and the first
 *   signal comes at 318 ms; then one every 100 ms, each with the two levels
 *   heard since, 135 to 190 ms after they ended. Not speech: the room, about
 *   -40 dBFS, -29 at the loudest after the start tick.
 */
.pragma library

var SPEECH = "QUTHQQOOKJLFGDIPTHHTXKPY]\\YZWYXXXXXVY[Z[U\\YYU]]SW]_`WXWZ`VXWX\\`U\\[ZYVRWNSYZYVVWQVWVVOWNNX]XTWZXWQVYLSVSQJMWXWSSUWW[[XVSSMSPUPPNGTVWXVSMOJSVQWU[WZXZ\\[]ZYTTXWWUXYYVTWXNPSMJKNFGILTXTSNKWSMUWLOVQOVVTNRVULNTVQVMOXYTTNVVLVXTVSWXTUUW\\\\XUPWYVTSUTOST\\TVNTXXW[\\Y\\VWSUR[Y[\\PLWTSVTPRPPRVWUQTVZVWPXZXZ\\^XXQ]\\X\\^RMHINDHLHGKFHTTNLGRXVTVZ][W[XVZZPRVUW[\\[W\\XZV]^VY^_`YWQY`XXUQ\\`U^ZXVWMPUXYYYVUPWVUXYQOOQY]XSTYWWOQXILGKNVUUXXSVVSV\\YXVUWTVXYTQNNVSTVWURVVVUTOS[X[YW[Z][XSPWPWWVSSLLSVMNQNMXXTVRMMTWUUPNPTXRSWUUXUTVTQWVSNLYWUPMTXXWUPPORSSVHRRPOV[]]YTPXXVTTUTOST[XXRMSWV[[W\\RSRUR[X\\\\POVVTQQMQOORVWUQTW[YVVZYW[\\^XYT]\\[\\^QWROOVXSNXTVWWTRMMRUSIUX\\[WZWVXWPRSVY\\ZZY][ZX^]TZ^``WVWY`VYXS\\_U]ZUSPKOOXWX[ULVSURXXMRUUW\\[UY[YWPYZPMHSWUTQXTQVVUV[[WWXVSWVWURWWVTYWSWSTWSUWTUZVZXY\\Z]ZVPOWPWTSVVSKSXUUUUPPPKIIKKMSVTVVURUXVWWTPXUFMRWVPPXYQMUTLTWVSVTTVVUWLRXWRRY][XWRWXVTTUTOS"
var ROOM_BUSY = "FFEHNEILHGKFGEIDJGGKMGPW\\[WZWVXWPRROW[ZYU\\XYU]]SW]_`WUOX`QWUQ[_U\\ZTSPKONSWXXPKHJRNQULONNW\\XSPYWWNQXILHKMKLPSSQSOKRZYTRQSLSOUPPNGMSTSNJJOHJKLNRZUZXW[Z]ZVPOWPWTSRSKJSVMOQMJKNGGIKKMKEJJKKMKOGKLQOKJELONHINJTIIMMLSPSNLNKQRSVGRRPOOW\\\\VTMVXVTSUTOSSZTVNMNOT[[V\\RSRUR[WZ[PLTRPLPKQOORVWUQTUWUQPXXSZ\\^UXR]\\X\\^"
var ROOM_QUIET = "MMIGFIFEJIKFIIDKJPJIMJLHJLKIFJIKJLIJKFHGOIKKHDLHKEHMMEEIKIJFKLHEGKDIFIHINJMIHJCIIEJGCHFGIMIIJDMFJFFHOKGHFIGKEHFGKIKMLEKDIOHHJIIGLLHJKLJKHFHLLIGJNMGIEFJILMLMGFKQJFJMFKGMKJOHGOFPIFIIJHLCGHNCHFGKJMGJMLHLFNIIJLNIHKFDLHLFCJINKJKHIEKGHKLFOGLLJJNLJDGLJFGHKJLGLGHNIIHHNMKJLIJJINNMCOKHILMLIIKIFGIJPEJIJMMIGEIMHKKJLIGELHHLGNKGGLEGIJIJHIMKHNCIKLIHKHJCJGLKKHJHJIFOKCLEHGGJHEIJNHEHKFGKIJGGHIHJKKJFFKIIFHGFGEILGIFKOEHMJICILMKGGDFLIEMDMHJKJMIHGEGLKMQKKEHPKIJCFECKLHJFJKNNJIGGKKINKIHIFFJGHMHMINJDMHCIIEGKMLMLCGJCKLGHFIIIFJHLJEEIHJKIDEKFLIKFICHKFFIIGKDLEGMFDIFFGGFFNGLEKEHKGCGIKFHIDIGJIICIHFGEJKKGNLFIDIKMHDHMIMKNKGJQ"
var ROOM_QUIET_SKEWED = "HQMLLKNKKJLIJKMTNOJOKKKJLNINKMJLMPMIHIKGIHGGIJGMHGOTRKMHLLLGIGHKVIIMNKKNHILJIKLKIPLMGHQGKIHJHIJOHHMMNJPLVJKKJIHTMJMKHHNNLKLIKNNOOIKGNMGNTHOOIIKLIKMKJKHIOMIKGLKJKMMMLPJKJHJJKKTKHIJPPKJNNROJMKKIJUOLQJIIIIIMJHQLJMKJLLKLHHMHHIMHILKIPMIHHHJRNHMJKKPKOINGILMNHPLIMIKINKNMNJJOOKKIILIMSJGIJNKLIJLMPIIRNIHIJKILHMNLKONIKILMHHKJKJHJMJGLKHMILIGKMLKHKLKPIHGLKKIMJLIJKLKOKOLKMNPIMKPKOMKKLIJLGJTRLMJLKKIINLRKKJIVMIHIKGJKPKHKPPGIHKHIMMIHKMIMRIKHPJILLOJIKJHJOJQIMLKKHJLIJIIHKKGJIJIPKQPLLVKQKIPKILMLLPPIJMJKHMHKJIJIKGOVMIQGGVHMKSNGIIMMNIOHIJPMOJKMMLIHLIJKJIKGHJIHLOUNLOOMKLJOIKQJLRKJKNNPMHLHOSIRJJNIHPIIJKIPILHLLHIIHJMM"
var NOTE_2230 = "DEGGDEQIR^LIGEAECBKWRaa`]\\_P^b_`_^`_OZ__]XQVYXUPL_`ZNP]ZW``VQLd`\\]V^X__ZYbcc`^]]Xad^PWWZR[_^JZVKK[US\\V][\\\\KLOYYPOKFCAAAAQXJX^cb^^a]VYYYYRBDDDGAAADWS^\\YY]ZSUOBARCBANAEAKROOQ`b`^XSAEDABAANCXbe`_XLOGPTT][]QRZ^ZSMW^ZZ\\UNbbc\\LPDBAMGTAABAAAAAAAAAAEAAFACAECACAAAEDEAAFDCAABAEDCACCAAAAAAADAAAACAAABBCCAAAAAAAAAAAAAABAABAAALJABAADCCTQVTQPSac^]b]]^aYZde_TX`b^\\[WPLQKXS_``YR]YS]^SbcaU[_a]ZSaSc_VUOXH[aac_dU][XX`Wbbdae[`\\[\\\\VT\\^\\PQPYXYYYZWQVVQNUTNMOVSMIPRFJIIIRJGCHCJIFEABKGIW[NYY\\[VU]^\\]_e_]ZQSXWUHO[\\TOYVNVXPPVUYTUMKLSTLIGJQQOOSW"

// The Levels signals of the hold of 2026-11-04 00:10:09, as they came.
var LIVE_0010 = [
    {at: 318.5, from: 129, cb: [-5306]},
    {at: 415.8, from: 179, cb: [-4841, -5225]},
    {at: 514.4, from: 279, cb: [-5689, -4716]},
    {at: 615.4, from: 379, cb: [-4512, -4075]},
    {at: 716.1, from: 479, cb: [-4089, -3499]},
    {at: 814.8, from: 579, cb: [-2933, -2857]},
    {at: 915.8, from: 679, cb: [-3502, -3638]},
    {at: 1014.5, from: 779, cb: [-2836, -3398]},
    {at: 1115.1, from: 879, cb: [-3599, -3380]},
    {at: 1214.4, from: 979, cb: [-3673, -3895]},
    {at: 1314.7, from: 1079, cb: [-4380, -3420]},
    {at: 1414.6, from: 1179, cb: [-3235, -3398]},
    {at: 1515, from: 1279, cb: [-4159, -3661]},
    {at: 1615.2, from: 1379, cb: [-3069, -3913]},
    {at: 1715, from: 1479, cb: [-2542, -3151]},
    {at: 1814.5, from: 1579, cb: [-3331, -4073]},
    {at: 1914.4, from: 1679, cb: [-4062, -3880]},
    {at: 2014.8, from: 1779, cb: [-3982, -4435]},
    {at: 2114.9, from: 1879, cb: [-4036, -4296]},
    {at: 2214.7, from: 1979, cb: [-3849, -4085]},
    {at: 2314.7, from: 2079, cb: [-4021, -4014]},
    {at: 2414.3, from: 2179, cb: [-2460, -2476]},
    {at: 2514.3, from: 2279, cb: [-3722, -4059]},
    {at: 2614.6, from: 2379, cb: [-4081, -3981]},
    {at: 2714.4, from: 2479, cb: [-4460, -4757]},
    {at: 2814.2, from: 2579, cb: [-5514, -4900]},
    {at: 2915.2, from: 2679, cb: [-4443, -4562]},
    {at: 3015.1, from: 2779, cb: [-4339, -4041]},
    {at: 3114.3, from: 2879, cb: [-4120, -4030]},
    {at: 3214.6, from: 2979, cb: [-4116, -3889]},
    {at: 3315.1, from: 3079, cb: [-3836, -4594]},
    {at: 3415.1, from: 3179, cb: [-4393, -3989]},
    {at: 3515.3, from: 3279, cb: [-4755, -4914]},
    {at: 3614.7, from: 3379, cb: [-4409, -4793]},
    {at: 3714.7, from: 3479, cb: [-5394, -5265]},
    {at: 3815, from: 3579, cb: [-4824, -3973]},
    {at: 3914.4, from: 3679, cb: [-3677, -3871]},
    {at: 4014.5, from: 3779, cb: [-4019, -3754]},
    {at: 4114.7, from: 3879, cb: [-4048, -4958]},
    {at: 4164.8, from: 3979, cb: [-3835]}
]
var LIVE_0010_KEEP = 518.0
var LIVE_0010_STOP = 4042.2

// A string of levels as dBFS values, one per 50 ms.
function decode(text) {
    var out = []
    for (var i = 0; i < text.length; i++)
        out.push(text.charCodeAt(i) - 125)
    return out
}

// The same, in the signal's unit: hundredths of a dBFS, from 50 * first ms.
function centibels(text) {
    return decode(text).map(function(db) { return db * 100 })
}

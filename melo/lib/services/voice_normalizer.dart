/// Utility to normalize spoken Khmer and mixed Khmer-English speech for Melo.
/// Converts phonetic Khmer misrecognitions into clean music terms
/// ('playlist', 'songs', 'album', etc.) and maps phonetic Khmer artist
/// names into their canonical searchable names.
class VoiceNormalizer {
  VoiceNormalizer._();

  static String normalize(String raw) {
    if (raw.trim().isEmpty) return raw;
    var text = raw;

    // 1. "Playlist" phonetic variations in Khmer and English
    // Handles all Google Speech STT km-KH misrecognitions (e.g. ភ័យលេស "phay les")
    text = text.replaceAll(
      RegExp(
        r'(?:ភ័យលេស|ភ័យលីស|ភ័យលេីស|ភ័យលើស|ភ័យលិស|ភ័យលិត|ភ្លេចលេស|ភ្លេចលីស|ផ្លេស|ផ្លេលីស|ផ្លេលីស្ត|ផ្លេយលីស|ផ្លេយលេស|ផ្លេលិស|ផេ្លលីស|ផេ្លលិស|ប្លេលីស|ប្លេលីស្ត|ប្លេលេស|ភេ្លលីស|ផ្លេសលីស|ភ្លេលីស|ភ្លេលីស្ត|ភ្លេលី|ផ្លេលី|ផ្លេលីត|ផ្លេលីដ|ផ្លេយលី|ប្លេលី|ប្លេលិត|ផ្លេលិក|ប្លេលីក|play\s*list|play-list|pleylist|play\s*lis)',
        caseSensitive: false,
      ),
      ' playlist ',
    );

    // 2. "Album" phonetic variations in Khmer and English
    text = text.replaceAll(
      RegExp(
        r'(?:អាល់ប៊ុម|អាលប៊ុម|អាល់ប៊ំ|អ៊ាល់ប៊ុម|អាលបុម|អាល់បុម|អាល់ប៊ូម|អាល់ប៊ឹម|អ៊ាល់ប៊ូម|អាល់ប៊ម|អែលប៊ុម|អ៊ែលប៊ុម|al\s*bum|el\s*bum|elbum)',
        caseSensitive: false,
      ),
      ' album ',
    );

    // 3. "Song / Songs" phonetic variations in Khmer and English
    text = text.replaceAll(
      RegExp(
        r'(?:សង្ស|សង់ស៍|សងស៍|សោង|សុង្ស|សង្ស៍|songs?|song)',
        caseSensitive: false,
      ),
      ' songs ',
    );
    // When spoken as standalone "សង" or "សុង" or "សង់" in music context
    text = text.replaceAll(
      RegExp(r'(?<=\s|^)(?:សង|សុង|សង់)(?=\s|$)', caseSensitive: false),
      ' songs ',
    );

    // 4. "Artist / Singer" variations
    text = text.replaceAll(
      RegExp(
        r'(?:អាទិស|អាទីស|អឺទិស|អាទិស្ត|អឺទីស|អាធីស|អាទីស្ត|អទិស|artists?)',
        caseSensitive: false,
      ),
      ' artist ',
    );

    // 5. "Music" variations
    text = text.replaceAll(
      RegExp(
        r'(?:ម្ញូស៊ីក|ម្ញូស៊ិក|ម្យូស៊ីក|ម្យូស៊ិក|ម្ញូសិក|មូស៊ីក|មូស៊ិក|ម្យូសិក|ម្ញូស៊ិច|ម្យូស៊ិច|musics?)',
        caseSensitive: false,
      ),
      ' music ',
    );

    // 6. "Track / Tracks" variations
    text = text.replaceAll(
      RegExp(r'(?:ត្រាក់|ត្រេក|ត្រែក|ត្រាក|ត្រេកស៍|tracks?)', caseSensitive: false),
      ' track ',
    );

    // 7. Moods, Genres & Music terms commonly spoken in English by Cambodians
    // Chill
    text = text.replaceAll(
      RegExp(r'(?:ឈីល|ឈៀល|ជៀល|ជីល|ឈីវ|ឈៀវ|ឈីល់|ឈៀល់)', caseSensitive: false),
      ' chill ',
    );
    // Sad
    text = text.replaceAll(
      RegExp(r'(?:សេដ|សែដ|សេត|សែត)', caseSensitive: false),
      ' sad ',
    );
    // Remix
    text = text.replaceAll(
      RegExp(r'(?:រីមិច|រីមិក|រិមិច|រីម៉ិច|រីម៉ិក|រេមិច|រេម៉ិច)', caseSensitive: false),
      ' remix ',
    );
    // Cover
    text = text.replaceAll(
      RegExp(r'(?:ខូវើ|ខូវឺ|កូវើ|ខូវ័រ|ខូវើរ|ខវើ|កូវឺ)', caseSensitive: false),
      ' cover ',
    );
    // Acoustic
    text = text.replaceAll(
      RegExp(r'(?:អាកូស្ទីក|អាគូស្ទីក|អាកូស្ទិក|អាកូស្ទីច)', caseSensitive: false),
      ' acoustic ',
    );
    // Lo-fi
    text = text.replaceAll(
      RegExp(r'(?:ឡូហ្វាយ|ឡូហ្វៃ|ឡូហ្វាយ៍|ឡូហ្វាយ៉|ឡូហ្វាយស៍|lo-?fi)', caseSensitive: false),
      ' lo-fi ',
    );
    // Pop
    text = text.replaceAll(
      RegExp(r'(?:ផប|ប៉ុប|ផុប|ប៉ប)', caseSensitive: false),
      ' pop ',
    );
    // Rock
    text = text.replaceAll(
      RegExp(r'(?:រ៉ក់|រ៉ក|រ៉កក៍)', caseSensitive: false),
      ' rock ',
    );
    // Rap
    text = text.replaceAll(
      RegExp(r'(?:រ៉េប|រ៉ាប់|រ៉ែប|រ៉ាប)', caseSensitive: false),
      ' rap ',
    );
    // Hip Hop
    text = text.replaceAll(
      RegExp(r'(?:ហ៊ីបហប|ហ៊ីបហប់|ហីបហប|ហ៊ីបហបស៍|hip-?hop)', caseSensitive: false),
      ' hip hop ',
    );
    // Vibe
    text = text.replaceAll(
      RegExp(r'(?:វ៉ាយប៍|វ៉ាយ|វ៉ៃប៍|វ៉ែប|វ៉ាយប|វាយប៍|vibes?)', caseSensitive: false),
      ' vibe ',
    );
    // Party
    text = text.replaceAll(
      RegExp(r'(?:ផាធី|ប៉ាទី|ផាតធី|ផារធី)', caseSensitive: false),
      ' party ',
    );
    // Dance
    text = text.replaceAll(
      RegExp(r'(?:ដេនស៍|ដានស៍|ដេន)', caseSensitive: false),
      ' dance ',
    );
    // Workout & Gym
    text = text.replaceAll(
      RegExp(r'(?:វើកអាវ|វើកអោត)', caseSensitive: false),
      ' workout ',
    );
    text = text.replaceAll(
      RegExp(r'(?:ជីម)', caseSensitive: false),
      ' gym ',
    );
    // Club
    text = text.replaceAll(
      RegExp(r'(?:ក្លឹប|ក្លិប)', caseSensitive: false),
      ' club ',
    );
    // Slow / Speed up / Bass / Piano / Guitar
    text = text.replaceAll(RegExp(r'(?:ស្លូ)', caseSensitive: false), ' slow ');
    text = text.replaceAll(
      RegExp(r'(?:ស្ពីដអាប់|ស្ពីដ\s*អាប់)', caseSensitive: false),
      ' speed up ',
    );
    text = text.replaceAll(RegExp(r'(?:ព្យាណូ|ពីយ៉ាណូ)', caseSensitive: false), ' piano ');
    text = text.replaceAll(RegExp(r'(?:ហ្គីតា|ហ្គីតារ)', caseSensitive: false), ' guitar ');

    // 8. Popular Cambodian artists phonetically transcribed in Khmer or English
    text = text.replaceAll(
        RegExp(r'(?:វណ្ណដា|វ៉ាន់ដា|ម៉ាន់\s*វណ្ណដា|វ៉ាន់\s*ដា|\bvanda\b|\bvan\s*da\b|\bvan\s*dah\b)', caseSensitive: false),
        ' VannDa ');
    text = text.replaceAll(
        RegExp(r'(?:ស៊ូលី\s*ផេង|ស៊ូលីផេង|ស៊ូ\s*លី\s*ផេង|\bsuly\s*pheng\b|\bsuli\s*pheng\b|\bsouly\s*pheng\b)', caseSensitive: false),
        ' Suly Pheng ');
    text = text.replaceAll(
        RegExp(r'(?:ថេណា|ថេនា|ថេណារ|\btena\b)', caseSensitive: false), ' Tena ');
    text = text.replaceAll(
        RegExp(r'(?:ជី\s*ដេវីត|ដេវីត|ជីដេវីត|ជី\s*ដេវិត|\bg-?devith\b|\bgdevith\b|\bg\s*devit\b)', caseSensitive: false),
        ' G-Devith ');
    text = text.replaceAll(
        RegExp(r'(?:ព្រាប\s*សុវត្ថិ|ព្រាបសុវត្ថិ|\bpreap\s*sovath\b)', caseSensitive: false),
        ' Preap Sovath ');
    text = text.replaceAll(
        RegExp(r'(?:ស៊ីន\s*ស៊ីសាមុត|ស៊ីនស៊ីសាមុត|ស៊ីសាមុត|\bsinn?\s*sisamouth\b|\bsinn?\s*sisamuth\b)', caseSensitive: false),
        ' Sinn Sisamouth ');
    text = text.replaceAll(
        RegExp(r'(?:រស់\s*សេរីសុទ្ធា|រស់សេរីសុទ្ធា|សេរីសុទ្ធា|\bros\s*sereysothea\b|\bros\s*serey\s*sothea\b)', caseSensitive: false),
        ' Ros Sereysothea ');
    text = text.replaceAll(
        RegExp(r'(?:ក្មេងខ្មែរ|ក្មេង\s*ខ្មែរ|\bkmeng\s*khmer\b)', caseSensitive: false), ' Kmeng Khmer ');
    text = text.replaceAll(
        RegExp(r'(?:រូតកូ|រុតកូ|\bruthko\b)', caseSensitive: false), ' Ruthko ');
    text = text.replaceAll(
        RegExp(r'(?:យូហៃ|យូ\s*ហៃ|\byuuhai\b|\byuu\s*hai\b)', caseSensitive: false), ' YuuHai ');
    text = text.replaceAll(
        RegExp(r'(?:ឱក\s*សុគន្ធកញ្ញា|ឱកសុគន្ធកញ្ញា|សុគន្ធកញ្ញា|\baok\s*sokunkanha\b|\bok\s*sokunkanha\b)', caseSensitive: false),
        ' Aok Sokunkanha ');
    text = text.replaceAll(
        RegExp(r'(?:ម៉ានិត|\bmanith\b)', caseSensitive: false), ' Manith ');
    text = text.replaceAll(
        RegExp(r'(?:ខេម|\bkhem\b)', caseSensitive: false), ' Khem ');
    text = text.replaceAll(
        RegExp(r'(?:វុទ្ធា|\bvuthea\b)', caseSensitive: false), ' Vuthea ');
    text = text.replaceAll(
        RegExp(r'(?:សុខ\s*ពិសី|សុខពិសី|\bsok\s*pisey\b)', caseSensitive: false), ' Sok Pisey ');
    text = text.replaceAll(
        RegExp(r'(?:មាស\s*សុខសោភា|មាសសុខសោភា|\bmeas\s*soksophea\b)', caseSensitive: false), ' Meas Soksophea ');
    text = text.replaceAll(
        RegExp(r'(?:ខេមរៈ\s*សិរីមន្ត|ខេមរៈសិរីមន្ត|សិរីមន្ត|\bkhemrak\s*sereymun\b)', caseSensitive: false), ' Khemrak Sereymun ');
    text = text.replaceAll(
        RegExp(r'(?:គូម៉ា|\bkuma\b)', caseSensitive: false), ' Kuma ');
    text = text.replaceAll(
        RegExp(r'(?:នីកូ|\bniko\b)', caseSensitive: false), ' Niko ');
    text = text.replaceAll(
        RegExp(r'(?:ទេព\s*បូព្រឹក្ស|ទេពបូព្រឹក្ស|\btep\s*boprek\b)', caseSensitive: false), ' Tep Boprek ');
    text = text.replaceAll(
        RegExp(r'(?:រ៉េត\s*ស៊ូហ្សាណា|ស៊ូហ្សាណា|\breth\s*suzana\b)', caseSensitive: false), ' Reth Suzana ');
    text = text.replaceAll(
        RegExp(r'(?:ពេជ្រ\s*សោភា|ពេជ្រសោភា|\bpich\s*sophea\b)', caseSensitive: false), ' Pich Sophea ');

    // 9. Popular Global Artists phonetically transcribed in Khmer
    text = text.replaceAll(
        RegExp(r'(?:ថេឡឺ\s*ស្វីហ្វ|ថេលើ\s*ស្វីប|ថេលើ|ថេល័រ\s*ស្វីហ្វ)', caseSensitive: false),
        ' Taylor Swift ');
    text = text.replaceAll(
        RegExp(r'(?:ចាស្ទីន\s*ប៊ីប៊ឺ|ចាស្ទីន|ចាស្ទីន\s*ប៊ីប៊ើរ)', caseSensitive: false),
        ' Justin Bieber ');
    text = text.replaceAll(
        RegExp(r'(?:ឌឹ\s*វីកខិន|វីកខិន|វីកអិន|\bweekend\b)', caseSensitive: false),
        ' The Weeknd ');
    text = text.replaceAll(
        RegExp(r'(?:ប្រ៊ូណូ\s*ម៉ាស|ប្រូណូ\s*ម៉ាស|ប្រ៊ូណូម៉ាស)', caseSensitive: false),
        ' Bruno Mars ');
    text = text.replaceAll(
        RegExp(r'(?:ដ្រេក|ដ្រែក)', caseSensitive: false), ' Drake ');
    text = text.replaceAll(
        RegExp(r'(?:អេមីនែម|អិមមីនែម)', caseSensitive: false), ' Eminem ');
    text = text.replaceAll(
        RegExp(r'(?:អេដ\s*ស៊ Sheeran|អ៊ែដ\s*សៀរ៉េន|អ៊ែដ\s*ស៊្រីរ៉េន)', caseSensitive: false),
        ' Ed Sheeran ');
    text = text.replaceAll(
        RegExp(r'(?:ប៊ីលី\s*អាយលីស|ប៊ីលី\s*អៃលីស)', caseSensitive: false),
        ' Billie Eilish ');
    text = text.replaceAll(
        RegExp(r'(?:អារីអាណា\s*ហ្គ្រេនដេ|អារីអាណា)', caseSensitive: false),
        ' Ariana Grande ');
    text = text.replaceAll(
        RegExp(r'(?:ឆាលី\s*ភូស|ឆាលី\s*ភុត)', caseSensitive: false),
        ' Charlie Puth ');
    text = text.replaceAll(
        RegExp(r'(?:ប៊ីធីអេស|ប៊ីធីអែស)', caseSensitive: false), ' BTS ');
    text = text.replaceAll(
        RegExp(r'(?:ប្លេកភីង|ប្ល៊ែកភីង)', caseSensitive: false), ' BLACKPINK ');

    // 10. Common English misrecognitions of spoken Khmer words (when English recognizer is active)
    text = text.replaceAll(
        RegExp(r'\b(?:robos|roboss|roboth|robost)\b', caseSensitive: false), ' របស់ ');
    text = text.replaceAll(
        RegExp(r'\b(?:chamrieng|cham\s*rieng)\b', caseSensitive: false), ' ចម្រៀង ');
    text = text.replaceAll(
        RegExp(r'\b(?:jong\s*ban|jongban)\b', caseSensitive: false), ' ចង់បាន ');
    text = text.replaceAll(
        RegExp(r'^(?:som|soam)\b', caseSensitive: false), 'សុំ ');

    // 11. Boundary Spacing: ensure clean spacing between Khmer script and Latin script/numbers
    // (Khmer characters \u1780-\u17FF do not use spaces, but loanwords like VannDa, playlist, etc. need clear separation)
    text = text.replaceAllMapped(
      RegExp(r'([\u1780-\u17FF])([a-zA-Z0-9])'),
      (m) => '${m[1]} ${m[2]}',
    );
    text = text.replaceAllMapped(
      RegExp(r'([a-zA-Z0-9])([\u1780-\u17FF])'),
      (m) => '${m[1]} ${m[2]}',
    );

    // 12. Repetition normalization
    text = text.replaceAll(
        RegExp(r'\bchill\s+chill\b', caseSensitive: false), 'chill');
    text = text.replaceAll(
        RegExp(r'\bsad\s+sad\b', caseSensitive: false), 'sad');
    text = text.replaceAll(RegExp(r'ថ្មី[\s]*ថ្មី'), 'ថ្មីៗ');
    text = text.replaceAll(RegExp(r'ចាស់[\s]*ចាស់'), 'ចាស់ៗ');
    text = text.replaceAll(RegExp(r'ពីរោះ[\s]*ពីរោះ'), 'ពីរោះៗ');
    text = text.replaceAll(RegExp(r'ពិរោះ[\s]*ពិរោះ'), 'ពិរោះៗ');
    text = text.replaceAll(RegExp(r'សប្បាយ[\s]*សប្បាយ'), 'សប្បាយៗ');

    // 13. Clean up duplicate spaces
    text = text.replaceAll(RegExp(r'\s+'), ' ').trim();

    return text;
  }
}

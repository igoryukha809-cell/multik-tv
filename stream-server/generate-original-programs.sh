#!/usr/bin/env bash
set -Eeuo pipefail

OUT_DIR="${1:-/tmp/multik-tv-originals}"
FONT="${2:-/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf}"
mkdir -p "$OUT_DIR"

make_show() {
  local slug="$1" title="$2" background="$3" accent="$4"
  local f1="$OUT_DIR/$slug-1.txt" f2="$OUT_DIR/$slug-2.txt" f3="$OUT_DIR/$slug-3.txt"
  local title_file="$OUT_DIR/$slug-title.txt"
  printf '%s\n' "$title" > "$title_file"
  case "$slug" in
    cosmos)
      printf 'Солнце — звезда.\nОно находится в центре\nСолнечной системы.' > "$f1"
      printf 'Свет от Солнца до Земли\nидёт примерно 8 минут\nи 20 секунд.' > "$f2"
      printf 'Луна не светится сама:\nмы видим солнечный свет,\nкоторый она отражает.' > "$f3"
      ;;
    nature)
      printf 'Растения используют\nсолнечный свет, чтобы\nсоздавать себе питание.' > "$f1"
      printf 'Пчёлы и другие опылители\nпомогают многим растениям\nобразовывать плоды.' > "$f2"
      printf 'Бамбук — одна из самых\nбыстрорастущих групп\nрастений на Земле.' > "$f3"
      ;;
    ocean)
      printf 'Океан покрывает около\n71 процента поверхности\nнашей планеты.' > "$f1"
      printf 'Синий кит — самое крупное\nиз известных животных\nна Земле.' > "$f2"
      printf 'Самые глубокие места океана\nуходят вниз почти на\n11 километров.' > "$f3"
      ;;
    water)
      printf 'Солнце нагревает воду,\nи часть её испаряется\nс поверхности водоёмов.' > "$f1"
      printf 'В атмосфере водяной пар\nохлаждается и образует\nмаленькие капли облаков.' > "$f2"
      printf 'Осадки возвращают воду\nна землю, и круговорот\nначинается снова.' > "$f3"
      ;;
    insects)
      printf 'Бабочки проходят путь\nот яйца до гусеницы,\nкуколки и взрослой особи.' > "$f1"
      printf 'У пчёл есть особый язык\nдвижений, помогающий\nпоказывать путь к цветам.' > "$f2"
      printf 'Насекомые — важная часть\nпищевых цепей и жизни\nмногих экосистем.' > "$f3"
      ;;
    inventions)
      printf 'GPS определяет положение\nпо сигналам нескольких\nнавигационных спутников.' > "$f1"
      printf 'Светодиоды превращают\nэлектричество в свет\nс высокой эффективностью.' > "$f2"
      printf 'Телескопы помогают учёным\nизучать далёкие планеты,\nзвёзды и галактики.' > "$f3"
      ;;
  esac

  ffmpeg -hide_banner -nostdin -loglevel error -y \
    -f lavfi -i "color=c=$background:s=1280x720:r=25:d=36" \
    -f lavfi -i "anullsrc=channel_layout=stereo:sample_rate=44100" \
    -vf "drawbox=x='60+35*sin(t*0.8)':y=35:w=1160:h=650:color=$accent@0.16:t=fill,drawbox=x='100+70*sin(t*1.1)':y=520:w=150:h=150:color=$accent@0.45:t=fill,drawbox=x='1000+55*cos(t*0.9)':y=90:w=90:h=90:color=white@0.22:t=fill,drawtext=fontfile=$FONT:textfile=$title_file:fontcolor=white:fontsize=58:x=(w-text_w)/2:y=105:shadowcolor=black@0.45:shadowx=3:shadowy=3,drawtext=fontfile=$FONT:textfile=$f1:fontcolor=white:fontsize=46:line_spacing=18:x=(w-text_w)/2:y=300:box=1:boxcolor=black@0.28:boxborderw=28:enable='between(t,0,12)',drawtext=fontfile=$FONT:textfile=$f2:fontcolor=white:fontsize=46:line_spacing=18:x=(w-text_w)/2:y=300:box=1:boxcolor=black@0.28:boxborderw=28:enable='between(t,12,24)',drawtext=fontfile=$FONT:textfile=$f3:fontcolor=white:fontsize=46:line_spacing=18:x=(w-text_w)/2:y=300:box=1:boxcolor=black@0.28:boxborderw=28:enable='between(t,24,36)',drawtext=fontfile=$FONT:text='МУЛЬТИК ТВ  •  УЗНАЁМ МИР ВМЕСТЕ':fontcolor=white@0.9:fontsize=22:x=(w-text_w)/2:y=650" \
    -map 0:v:0 -map 1:a:0 -t 36 -c:v libx264 -preset ultrafast -pix_fmt yuv420p -r 25 -g 50 \
    -c:a aac -b:a 48k -ar 44100 -ac 2 -shortest "$OUT_DIR/$slug.mp4"
}

make_show cosmos "КОСМОС РЯДОМ" "0x10234f" "0x62c8ff"
make_show nature "УДИВИТЕЛЬНАЯ ПРИРОДА" "0x124b3a" "0x9be564"
make_show ocean "МИР ОКЕАНОВ" "0x073b66" "0x53d8fb"
make_show water "ПУТЕШЕСТВИЕ КАПЛИ" "0x174a66" "0x71d7ff"
make_show insects "МИР НАСЕКОМЫХ" "0x3b4d20" "0xd6e86a"
make_show inventions "ИЗОБРЕТЕНИЯ ВОКРУГ НАС" "0x38245f" "0xffc86b"
make_show quiz "ВОПРОС ДНЯ" "0x56366f" "0xffd56a"
make_show history "ИСТОРИИ ИЗОБРЕТЕНИЙ" "0x214c66" "0x69d5cb"

echo "Созданы 8 авторских выпуска: Космос рядом, Удивительная природа, Мир океанов, Путешествие капли, Мир насекомых, Изобретения вокруг нас, Вопрос дня, Истории изобретений."

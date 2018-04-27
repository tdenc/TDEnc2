#!/bin/bash
# vim:set ts=2 sw=2 tw=0 ft=sh:

# `cd` to "tool" derectory
current_dir="$(dirname "$0")"
cd "${current_dir}"

### Variables ### {{{
# version of this script and x264
current_version="2.98"
current_x264_version=2358

# make a directory for temporary files
# use PID for multiple-running
temp_dir="temp/$$"
mkdir -p "${temp_dir}" >/dev/null 2>&1
temp_264="${temp_dir}/video.h264"
temp_wav="${temp_dir}/audio.wav"
temp_m4a="${temp_dir}/audio.m4a"
temp_mp4="${temp_dir}/movie.mp4"
ver_txt="current_version"
[ -s "${ver_txt}" ] && current_version=$(cat "${ver_txt}")

# read user settings
# edit message.conf to use TDEnc2 in your native language :)
. "../setting/message.conf"
. "../setting/default_setting"
. "../setting/user_setting.conf"
. "../setting/x264_option.conf"
. "../setting/ffmpeg_option.conf"
[ -d "${mp4_dir}" ] || mkdir -p "${mp4_dir}" >/dev/null 2>&1

# escape sequence
if $(echo "${TERM}" | grep -iq 'xterm'); then
  color_green=$'\e[32m'
  color_blue=$'\e[34m'
  color_red=$'\e[31m'
  color_purple=$'\e[35m'
  color_reset=$'\e[0m'
else
  color_green=""
  color_blue=""
  color_red=""
  color_purple=""
  color_reset=""
fi

# prompt for `select`
PS3=">> "

# }}}

### Data Structures ### {{{
# i wish i could use bash 4 for associative arrays...
# question_info    = (
#              [0]    question_type       : 1-3 ( 1:easy, 3:difficult )
#              [1]    site_type           : 1-4 ( 1:niconico(old), 2:niconico(new), 3:youtube, 4:twitter )
#              [2]    preset_type         : 1-9 ( 7:sing, 8:user-preset ,9:youtube )
#              [3]    account_type        : 1-2 ( 1:premium, 2:normal )
#              [4]    enc_type            : 1-2 ( 1:high, 2:economy )
#              [5]    crf_type            : 1-3 ( 1:auto, 2:no, 3:manual )
#              [6]    dec_type            : 1-2 ( 1:fast, 2:normal )
#              [7]    flash_type          : 1-3 ( 1:normal, 3:strict )
#              [8]    deint_type          : 1-2 ( 1:auto, 2:no, 3:force )
#              [9]    resize_type         : 1-2 ( 1:auto, 2:no, 3:manual )
#              [10]   total_time_sec      : int
#              [11]   o_video_width       : int
#              [12]   o_video_height      : int
#              [13]   crf_value           : float
#              [14]   video_bitrate       : int
#              [15]   audio_bitrate       : int
#              [16]   audio_samplingrate  : 1-4 ( 1:44100, 2:48000, 3:96000, 4:same as source )
#              [17]   samplingrate_value  : int
#              [18]   limit_bitrate       : int
#              [19]   denoise_type        : 1-3 ( 1:auto, 2:yes, 3:no )
#                    )
# video_info   = (
#           [0]   Duration
#           [1]   BitRate
#           [2]   FrameRate
#           [3]   Width
#           [4]   Height
#           [5]   DisplayAspectRatio
#           [6]   PixelAspectRatio
#           [7]   ScanType
#                )
# audio_info   = (
#           [0]   Duration
#           [1]   BitRate
#           [2]   SamplingRate
#           [3]   Channels
#                )
# }}}

### Functions ### {{{
tdeHandler()
{
  # delete temporary files when C-c
  rm -rf "${temp_dir}"
  exit 1
}

tdeError()
{
  # if you dont want to delete log files for debugging, comment out the following line
  rm -rf "${temp_dir}"
  read -p " ${pause_message1}"
  echo "${color_blue}${border_line}${color_reset}" >&2
  exit 1
}

tdeSuccess()
{
  rm -rf "${temp_dir}"
  read -p " ${pause_message2}"
  echo "${color_blue}${border_line}${color_reset}" >&2
  [ "${os}" = "Mac" ] && open "${mp4_dir}"
  exit 0
}

# Usage: tdeEcho ${long_message}
tdeEcho()
{
  echo "" >&2
  echo "${color_blue}${border_line}" >&2
  for item in "$@"
  do
    echo " ${color_reset}${item}" >&2
  done
  echo "${color_blue}${border_line}${color_reset}" >&2
}

# Usage: tdeEchoS ${short_message}
tdeEchoS()
{
  echo "" >&2
  echo "${color_purple}${short_line}" >&2
  for item in "$@"
  do
    echo " ${color_reset}${item}" >&2
  done
  echo "${color_purple}${short_line}${color_reset}" >&2
  sleep 1
}

# Usage: tdeMin "${int1}" "${int2}" ( returns the smaller )
tdeMin()
{
  [ "$1" -le $2 ] && echo $1 || echo $2
}

# Usage: tdeMax "${int1}" "${int2}" ( returns the larger )
tdeMax()
{
  [ "$1" -ge $2 ] && echo $1 || echo $2
}

# Usage: tdeBc "${float1} + ${float2}" ( returns the result )
#        tdeBc "${float1} > ${float2}" ( returns 1 if true, 0 if false )
tdeBc()
{
  echo "scale=3; $1" | bc
}

# Usage: tdeMediaInfo -v[-i|-a|-g] "${Param}" "${input_filename}"
tdeMediaInfo()
{
  case "$1" in
    -v) media_param="Video";;
    -i) media_param="Image";;
    -a) media_param="Audio";;
    -g) media_param="General";;
  esac
  ${tool_mediainfo} --Inform\=${media_param}\;%"$2"% "$3"
}

# tdeVideoInfo() for video_info[]
tdeVideoInfo()
{
  local video_duration=$(tdeMediaInfo -v Duration "$1")
  local video_bitrate=$(tdeMediaInfo -v BitRate "$1")
  local video_fps=$(tdeMediaInfo -v FrameRate "$1")
  local video_width video_height
  image_pattern="jpe?g|png|bmp|tif+"
  if [[ ${video_ext} =~ ${image_pattern} ]]; then
    video_width=$(tdeMediaInfo -i Width "$1")
    video_height=$(tdeMediaInfo -i Height "$1")
  else
    video_width=$(tdeMediaInfo -v Width "$1")
    video_height=$(tdeMediaInfo -v Height "$1")
  fi
  local video_dar=$(tdeMediaInfo -v DisplayAspectRatio "$1")
  local video_par=$(tdeMediaInfo -v PixelAspectRatio "$1")
  local video_scantype=$(tdeMediaInfo -v ScanType "$1")
  cat <<EOF
  ${video_duration:-0}
  ${video_bitrate:-0}
  ${video_fps:-30}
  ${video_width:-0}
  ${video_height:-0}
  ${video_dar:-1.778}
  ${video_par:-1}
  ${video_scantype:-Progressive}
EOF
}

# tdeAudioInfo() for audio_info[]
tdeAudioInfo()
{
  local audio_duration=$(tdeMediaInfo -a Duration "$1")
  local audio_bitrate=$(tdeMediaInfo -a BitRate "$1")
  local audio_samplingrate=$(tdeMediaInfo -a SamplingRate "$1")
  local audio_channels=$(tdeMediaInfo -a Channels "$1")
  cat <<EOF
  ${audio_duration:-0}
  ${audio_bitrate:-0}
  ${audio_samplingrate:-48000}
  ${audio_channels:-2}
EOF
  tdeEchoS "${analyze_end}" >&2
}

# Usage: tdeShowInfo "${video_filename}" ["${audio_filename}"]
tdeShowInfo()
{
  local na="N/A"
  local input_audio
  [ "$#" -eq 1 ] && input_audio="$1" || input_audio="$2"

  local file_format=$(tdeMediaInfo -g Format "$1")\ \($(tdeMediaInfo -g FileExtension "$1")\)
  local file_size=$(tdeMediaInfo -g FileSize/String "$1")
  local total_bitrate=$(tdeMediaInfo -g OverallBitRate/String "$1")
  local duration=$(tdeMediaInfo -g Duration/String "$1")

  local video_format=$(tdeMediaInfo -v Format "$1")
  local video_width=$(tdeMediaInfo -v Width/String "$1")
  local video_height=$(tdeMediaInfo -v Height/String "$1")
  local video_bitrate=$(tdeMediaInfo -v BitRate/String "$1")
  local video_framerate=$(tdeMediaInfo -v FrameRate/String "$1")
  local video_aspect_ratio=$(tdeMediaInfo -v DisplayAspectRatio/String "$1")

  local image_format=$(tdeMediaInfo -i Format "$1")
  local image_width=$(tdeMediaInfo -i Width/String "$1")
  local image_height=$(tdeMediaInfo -i Height/String "$1")

  local audio_format=$(tdeMediaInfo -a Format "${input_audio}")
  local audio_bitrate=$(tdeMediaInfo -a BitRate/String "${input_audio}")
  local audio_samplingrate=$(tdeMediaInfo -a SamplingRate/String "${input_audio}")
  local audio_channels=$(tdeMediaInfo -a Channels "${input_audio}")

  cat <<EOF
 File Format         : ${file_format:-${na}}
 File Size           : ${file_size:-${na}}
 Total Bitrate       : ${total_bitrate:-${na}}
 Duration            : ${duration:-${na}}
 Video(Image) Format : ${video_format:-${image_format}}
 Video(Image) Width  : ${video_width:-${image_width}}
 Video(Image) Height : ${video_height:-${image_height}}
 Video Bitrate       : ${video_bitrate:-${na}}
 Framerate           : ${video_framerate:-${na}}
 Aspect Ratio        : ${video_aspect_ratio:-${na}}
 Audio Format        : ${audio_format:-${na}}
 Audio Bitrate       : ${audio_bitrate:-${na}}
 Samlingrate         : ${audio_samplingrate:-${na}}
 Channels            : ${audio_channels:-${na}}
EOF
}

tdeAskQuestion()
{
  # define local variables
  local question_type="${question_type}"
  local site_type="${site_type}"
  local preset_type="${preset_type}"
  local account_type="${account_type}"
  local enc_type="${enc_type}"
  local total_bitrate="${total_bitrate}"
  local crf_type="${crf_type}"
  local crf_value="${crf_value}"
  local dec_type="${dec_type}"
  local flash_type="${flash_type}"
  local deint_type="${deint_type}"
  local resize_type="${resize_type}"
  local resize_value="${resize_value}"
  local audio_bitrate="${audio_bitrate}"
  local audio_samplingrate="${audio_samplingrate}"
  local denoise_type="${denoise_type}"
  local skip_mode="${skip_mode}"
  local ret str
  local x264_pass
  local account_type account_start1 account_start2 account_list1 account_list2
  local limit_bitrate
  local temp_total_bitrate
  local a_max_bitrate
  local video_bitrate
  local samplingrate_value
  local confirm_end

  # additional variables for bitrate and video resolution
  local total_time_sec=$(tdeMax "${video_info[0]}" "${audio_info[0]}")
        total_time_sec=$(( (${total_time_sec} + 500) / 1000 ))
  local p_temp_bitrate=$(tdeBc "${size_premium} * 1024 * 8 / ${total_time_sec}")
        p_temp_bitrate=${p_temp_bitrate%%[\.]*}
  local i_temp_bitrate=$(tdeBc "${size_normal} * 1024 * 8 / ${total_time_sec}")
        i_temp_bitrate=${i_temp_bitrate%%[\.]*}
  local p_temp_bitrate_new=$(tdeBc "${size_premium_new} * 1024 * 8 / ${total_time_sec}")
        p_temp_bitrate_new=${p_temp_bitrate_new%%[\.]*}
  local y_p_temp_bitrate=$(tdeBc "${size_youtube_partner} * 1024 * 8 / ${total_time_sec}")
        y_p_temp_bitrate=${y_p_temp_bitrate%%[\.]*}
  local y_i_temp_bitrate=$(tdeBc "${size_youtube_normal} * 1024 * 8 / ${total_time_sec}")
        y_i_temp_bitrate=${y_i_temp_bitrate%%[\.]*}
  local tw_temp_bitrate=$(tdeBc "${size_twitter} * 1024 * 8 / ${total_time_sec}")
        tw_temp_bitrate=${tw_temp_bitrate%%[\.]*}
  local s_v_bitrate=$(tdeBc "${video_info[1]} / 1000")
        s_v_bitrate=${s_v_bitrate%%[\.]*}
  local i_video_height="${video_info[4]}"
  local o_video_height=$((${auto_height} + ${auto_height} % 2))
  local i_video_width=$(tdeBc "${video_info[3]} * ${video_info[6]}")
        i_video_width=${i_video_width%%[\.]*}
        i_video_width=$((${i_video_width} + ${i_video_width} % 2))
  if [ -n "${auto_width}" ]; then
    local o_video_width=$((${auto_width} + ${auto_width} % 2))
  else
    local o_video_width=$(tdeBc "${auto_height} * ${i_video_width} / ${video_info[4]}")
          o_video_width=${o_video_width%%[\.]*}
          o_video_width=$((${o_video_width} + ${o_video_width} % 2))
  fi
  local o_video_height_new_h=$((${auto_height_new_h} + ${auto_height_new_h} % 2))
  local o_video_width_new_h=$(tdeBc "${auto_height_new_h} * ${i_video_width} / ${video_info[4]}")
        o_video_width_new_h=${o_video_width_new_h%%[\.]*}
        o_video_width_new_h=$((${o_video_width_new_h} + ${o_video_width_new_h} % 2))
  local o_video_height_new_m=$((${auto_height_new_m} + ${auto_height_new_m} % 2))
  local o_video_width_new_m=$(tdeBc "${auto_height_new_m} * ${i_video_width} / ${video_info[4]}")
        o_video_width_new_m=${o_video_width_new_m%%[\.]*}
        o_video_width_new_m=$((${o_video_width_new_m} + ${o_video_width_new_m} % 2))
  local o_video_height_new_l=$((${auto_height_new_l} + ${auto_height_new_l} % 2))
  local o_video_width_new_l=$(tdeBc "${auto_height_new_l} * ${i_video_width} / ${video_info[4]}")
        o_video_width_new_l=${o_video_width_new_l%%[\.]*}
        o_video_width_new_l=$((${o_video_width_new_l} + ${o_video_width_new_l} % 2))
  local o_video_height_twitter=$((${auto_height_twitter} + ${auto_height_twitter} % 2))
  local o_video_width_twitter=$(tdeBc "${auto_height_twitter} * ${i_video_width} / ${video_info[4]}")
        o_video_width_twitter=${o_video_width_twitter%%[\.]*}
        o_video_width_twitter=$((${o_video_width_twitter} + ${o_video_width_twitter} % 2))

  # start question
  tdeEcho $question_start{1,2}

  # question level
  case "${question_type}" in
    1|2|3) ;;
    *)
      tdeEcho $level_start{1..3}
      select item in $level_list{1..3}
      do
        [ -z "${item}" ] && tdeEcho ${return_message1} && continue
        question_type="${REPLY}"
        break
      done
      ;;
  esac
  if [ "${question_type}" -le 2 ]; then
    crf_type=1
    enc_type=1
    dec_type=2
    deint_type=1
    audio_samplingrate=1
    if [ "${question_type}" -eq 1 ]; then
      preset_type=2
      total_bitrate=0
      flash_type=1
      resize_type=1
      denoise_type=1
    fi
  fi

  # upload site
  case "${site_type}" in
    1|2|3|4) ;;
    *)
      tdeEcho "${site_type_start}"
      select item in "NicoNico(old)" "NicoNico(new)" "YouTube" "Twitter"
      do
        [ -z "${item}" ] && tdeEcho ${return_message1} && continue
        site_type="${REPLY}"
        break
      done
      ;;
  esac
  if [ "${site_type}" -eq 1 ]; then
    if [ "${old_nico_feature}" != "true" ]; then
      tdeEcho $premium_error{1..3} && tdeError
    fi
  elif [ "${site_type}" -eq 2 ]; then
    y_account_type=1
    preset_type=9
    audio_samplingrate=1
    enc_type=1
    crf_type=1
    dec_type=2
    flash_type=1
  elif [ "${site_type}" -eq 3 ]; then
    preset_type=9
    audio_samplingrate=2
    enc_type=1
    crf_type=1
    dec_type=2
    resize_type=2
    flash_type=1
  elif [ "${site_type}" -eq 4 ]; then
    preset_type=9
    enc_type=1
    crf_type=1
    dec_type=2
    flash_type=1
    total_bitrate=0
  fi

  # choose preset
  case "${preset_type}" in
    [1-9]) ;;
    *)
      tdeEcho $preset_start{1,2}
      select item in $preset_list{1..8}
      do
        [ -z "${item}" ] && tdeEcho ${return_message1} && continue
        [ "${REPLY}" -eq 7 -a "${video_ext}" != "mp4" ] && tdeEcho "${preset_message}" && continue
        preset_type="${REPLY}"
        break
      done
      ;;
  esac
  case "${preset_type}" in
    1|4)
      crf_type=2
      denoise_type=3
      ;;
    7)
      crf_type=2
      deint_type=3
      flash_type=1
      dec_type=2
      resize_type=2
      total_bitrate="${p_temp_bitrate}"
      ;;
    8)
      enc_type=1
      dec_type=2
      ;;
  esac

  # choose account type
  if [ "${site_type}" -eq 4 ]; then
    account_type=1
  elif [ "${preset_type}" -ne 9 ]; then
    account_type="${n_account_type}"
    account_start1="${premium_start1}"
    account_start2="${premium_start2}"
    account_list1="${premium_list1}"
    account_list2="${premium_list2}"
  else
    account_type="${y_account_type}"
    account_start1="${premium_start3}"
    account_start2="${premium_start4}"
    account_list1="${premium_list3}"
    account_list2="${premium_list4}"
  fi
  case "${account_type}" in
    1|2) ;;
    *)
      tdeEcho $account_start{1,2}
      select item in $account_list{1,2}
      do
        [ -z "${item}" ] && tdeEcho ${return_message1} && continue
        account_type="${REPLY}"
        break
      done
      ;;
  esac
  if [ "${preset_type}" -eq 9 -a "${account_type}" -eq 2 ]; then
    ret=$(tdeBc "${total_time_sec} >= ${youtube_duration}")
    [ "${ret}" -eq 1 ] && tdeEcho $youtube_error{1,2} && tdeError
  fi

  # economy mode
  case "${enc_type}" in
    1|2) ;;
    *)
      tdeEcho ${economy_start1}
      select item in $economy_list{1,2}
      do
        [ -z "${item}" ] && tdeEcho ${return_message1} && continue
        enc_type="${REPLY}"
        break
      done
      ;;
  esac
  if [ "${enc_type}" -eq 2 ]; then
    limit_bitrate="${e_max_bitrate}"
    if [ "${account_type}" -eq 1 ]; then
      total_bitrate=$(tdeMin "${e_max_bitrate}" "${p_temp_bitrate}")
    else
      total_bitrate=$(tdeMin "${e_max_bitrate}" "${i_temp_bitrate}")
    fi
  fi

  # total bitrate
  if [ "${site_type}" -eq 3 ]; then
    if [ "${account_type}" -eq 1 ]; then
      total_bitrate="${y_p_temp_bitrate}"
      limit_bitrate="${y_p_temp_bitrate}"
    else
      total_bitrate="${y_i_temp_bitrate}"
      limit_bitrate="${y_i_temp_bitrate}"
    fi
  elif [ "${site_type}" -eq 4 ]; then
    total_bitrate="${tw_temp_bitrate}"
    limit_bitrate="${tw_temp_bitrate}"
  elif [ "${site_type}" -eq 2 ]; then
    if [ "{zenza}" = "true" ]; then
      total_bitrate="${p_temp_bitrate}"
      limit_bitrate="${p_temp_bitrate}"
    else
      total_bitrate="${p_temp_bitrate_new}"
      limit_bitrate="${p_temp_bitrate_new}"
    fi
  else
    if [ "${account_type}" -eq 1 ]; then
      limit_bitrate="${p_temp_bitrate}"
      str=$(echo -n "${total_bitrate}" |sed 's/[0-9]//g')
      if [ -z "${total_bitrate}" -o -n "${str}" ]; then
        tdeEcho $bitrate_start{1,2}
        while read -p "$PS3" input
        do
          str=$(echo -n "${input}" |sed 's/[0-9]//g')
          [ -z "${input}" -o -n "${str}" ] && tdeEcho "${return_message2}" && continue
          ret=$(tdeBc "${input} > ${limit_bitrate}")
          if [ "${ret}" -eq 1 ]; then
            tdeEcho $return_message{3..5}
            tdeEchoS "${limit_message1}${limit_bitrate}"
            continue
          fi
          total_bitrate="${input}"
          temp_total_bitrate=$(tdeMin "${total_bitrate}" "${p_temp_bitrate}")
          break
        done
      fi
      [ "${total_bitrate}" -eq 0 ] && total_bitrate="${limit_bitrate}"
    else
      limit_bitrate="${i_max_bitrate}"
      total_bitrate=$(tdeMin "${i_temp_bitrate}" "${i_target_bitrate}")
    fi
  fi

  # crf encode
  [ "${total_bitrate}" -lt ${bitrate_threshold} ] && crf_type=2
  [ -n "${crf_value}" ] && crf_type=3
  case "${crf_type}" in
    [1-3]) ;;
    *)
      tdeEcho $br_mode_start{1..4}
      select item in $br_mode_list{1..3}
      do
        [ -z "${item}" ] && tdeEcho ${return_message1} && continue
        crf_type="${REPLY}"
        break
      done
      ;;
  esac
  case "${crf_type}" in
    1)
      if [ "${site_type}" -ne 1 ]; then
        crf_value="${crf_you}"
      elif [ "${account_type}" -eq 1 ]; then
        crf_value="${crf_high}"
      else
        crf_value="${crf_low}"
      fi
      ;;
    2)
      crf_value=-1
      ;;
    3)
      while [ -z "${crf_value}" ]
      do
        tdeEcho $crf_value_start{1,2}
        while read -p "$PS3" input
        do
          [ -z "${input}" ] && tdeEcho "${return_message7}" && continue
          ret=$(tdeBc "${input} > 0")
          [ "${ret}" -eq 0 ] && tdeEcho "${return_message7}" && continue
          crf_value="${input}"
          break
        done
      done
      ;;
  esac

  # fast decode
  case "${dec_type}" in
    1|2) ;;
    *)
      tdeEcho $decode_start{1..4}
      select item in $decode_list{1,2}
      do
        [ -z "${item}" ] && tdeEcho ${return_message1} && continue
        dec_type="${REPLY}"
        break
      done
      ;;
  esac

  # flash player
  case "${flash_type}" in
    1|2) ;;
    *)
      tdeEcho $flash_start{1..5}
      select item in $flash_list{1..3}
      do
        [ -z "${item}" ] && tdeEcho ${return_message1} && continue
        flash_type="${REPLY}"
        break
      done
      ;;
  esac

  # deinterlace
  case "${deint_type}" in
    [1-3]) ;;
    *)
      tdeEcho ${deint_start1}
      select item in $deint_list{1..3}
      do
        [ -z "${item}" ] && tdeEcho ${return_message1} && continue
        deint_type="${REPLY}"
        break
      done
      ;;
  esac

  # video resize
  case "${resize_type}" in
    [1-3]) ;;
    *)
      tdeEcho $resize_start{1..3}
      select item in $resize_list{1..3}
      do
        [ -z "${item}" ] && tdeEcho ${return_message1} && continue
        resize_type="${REPLY}"
        break
      done
      ;;
  esac
  if [ "${resize_type}" -eq 2 ]; then
    o_video_width="${i_video_width}"
    o_video_height="${i_video_height}"
  elif [ "${resize_type}" -eq 1 ]; then
    if [ "${site_type}" -eq 2 ];then
      if [ "${total_time_sec}" -le ${nico_new_duration_m} ]; then
        if [ "${total_bitrate}" -lt ${bitrate_nico_new_threshold_m} ]; then
          o_video_width=${o_video_width_new_m}
          o_video_height=${o_video_height_new_m}
        else
          o_video_width=${o_video_width_new_h}
          o_video_height=${o_video_height_new_h}
        fi
      else
        o_video_width=${o_video_width_new_l}
        o_video_height=${o_video_height_new_l}
      fi
    elif [ "${site_type}" -eq 4 ];then
      o_video_width=${o_video_width_twitter}
      o_video_height=${o_video_height_twitter}
    fi
  else
    while [ -z "${resize_value}" ]
    do
      tdeEcho ${resize_value_start}
      while read -p "$PS3" input
      do
        [ -z "${input}" ] && tdeEcho "${return_message7}" && continue
        str=$(echo -n "${input}" |sed 's/[0-9]//g')
        if [[ "${str}" =~ [:x] ]]; then
          o_video_width=${input%%[:x]*}
          o_video_height=${input##*[:x]}
          if [ -n "${o_video_width}" -a -n "${o_video_height}" ]; then
            resize_value="${input}"
            break
          fi
        fi
        tdeEcho "${return_message7}"
        continue
      done
    done
  fi
  if [ "${site_type}" -eq 1 -a "${account_type}" -eq 2 ]; then
    if [ "${o_video_width}" -gt ${i_max_width} -o "${o_video_height}" -gt ${i_max_height} ]; then
      [ "${preset_type}" -eq 7 ] && tdeEcho $return_message{8,9} || tdeEcho $return_message{10,11}
      tdeError
    fi
  elif [ "${site_type}" -eq 4 ]; then
    if [ "${o_video_width}" -gt ${t_max_width} -o "${o_video_height}" -gt ${t_max_height} ]; then
      tdeEcho $return_message{12,13}
      tdeError
    fi
  fi

  # denoise
  case "${denoise_type}" in
    [1-3]) ;;
    *)
      tdeEcho ${denoise_start1}
      select item in $denoise_list{1..3}
      do
        [ -z "${item}" ] && tdeEcho ${return_message1} && continue
        denoise_type="${REPLY}"
        break
      done
      ;;
  esac

  # audio bitrate
  if [ "${preset_type}" -eq 7 ];then
    a_max_bitrate=$((${total_bitrate} - ${s_v_bitrate}))
  else
    a_max_bitrate=${total_bitrate}
    if [ "${site_type}" -eq 3 ]; then
      if [ "${audio_info[3]}" -eq 2 ]; then
        audio_bitrate="${y_stereo_bitrate}"
      else
        audio_bitrate="${y_surround_bitrate}"
      fi
    elif [ "${site_type}" -eq 2 ]; then
        audio_bitrate=${a_bitrate_nico_new}
    elif [ "${site_type}" -eq 4 ]; then
        audio_bitrate=${a_bitrate_twitter}
    elif [ "${question_type}" -eq 1 ]; then
      if [ "${account_type}" -eq 1 ]; then
        audio_bitrate=192
      else
        audio_bitrate=128
      fi
    fi
  fi
  [ "${a_max_bitrate}" -lt 0 ] && tdeEcho $return_message{5,6} && tdeError
  str=$(echo -n "${audio_bitrate}" |sed 's/[0-9]//g')
  if [ -z "${audio_bitrate}" -o -n "${str}" ]; then
    tdeEcho $audio_start{1..3}
    while read -p "$PS3" input
    do
      str=$(echo -n "${input}" |sed 's/[0-9]//g')
      [ -z "${input}" -o -n "${str}" ] && tdeEcho "${return_message2}" && continue
      ret=$(tdeBc "${input} > ${a_max_bitrate}")
      if [ "${ret}" -eq 1 ]; then
        tdeEcho $return_message{3,4}
        tdeEcho "${limit_message1}${a_max_bitrate}"
        continue
      fi
      input=$(tdeMin "${input}" "${n_a_limit_bitrate}")
      if [ "${preset_type}" -eq 7 ]; then
        ret=$((${s_v_bitrate} + ${input}))
      else
        ret=$((${total_bitrate} - ${input}))
      fi
      if [ "${ret}" -le 0 ]; then
        tdeEcho $return_message{3,4}
        continue
      fi
      audio_bitrate="${input}"
      break
    done
  fi
  if [ "${preset_type}" -eq 7 ]; then
    video_bitrate="${s_v_bitrate}"
    total_bitrate=$((${s_v_bitrate} + ${audio_bitrate}))
  else
    video_bitrate=$((${total_bitrate} - ${audio_bitrate}))
  fi

  # audio samplingrate
  case "${audio_samplingrate}" in
    [1-4]) ;;
    *)
      tdeEcho $samplingrate_start{1,2}
      select item in $samplingrate_list{1..4}"Hz"
      do
        [ -z "${item}" ] && tdeEcho ${return_message1} && continue
        audio_samplingrate="${REPLY}"
        break
      done
      ;;
  esac
  case "${audio_samplingrate}" in
    2)
      samplingrate_value="${samplingrate_list2}"
      ;;
    3)
      samplingrate_value="${samplingrate_list3}"
      ;;
    4)
      samplingrate_value="0"
      ;;
    *)
      samplingrate_value="${samplingrate_list1}"
      ;;
  esac

  # confirm
  case "${skip_mode}" in
    1)
      ;;
    *)
      local confirm_preset0="preset_list${preset_type}"
      if [ "${site_type}" -eq 1 ]; then
        if [ "${account_type}" -eq 1 ]; then
          local confirm_account0="confirm_account1"
        else
          local confirm_account0="confirm_account2"
        fi
      elif [ "${site_type}" -eq 2 ]; then
        local confirm_account0="confirm_account3"
      elif [ "${site_type}" -eq 4 ]; then
        local confirm_account0="confirm_account6"
      else
        if [ "${account_type}" -eq 1 ]; then
          local confirm_account0="confirm_account4"
        else
          local confirm_account0="confirm_account5"
        fi
      fi
      local confirm_player0="confirm_player${flash_type}"
      local confirm_dectype0="confirm_${dec_type}"
      local confirm_deint0="confirm_deint${deint_type}"
      local confirm_denoise0="confirm_denoise${denoise_type}"
      if [ "${audio_bitrate}" -eq 0 ]; then
        local confirm_audio0="${confirm_no_audio}"
      else
        local confirm_audio0="${audio_bitrate}kbps"
      fi
      if [ "${crf_type}" -eq 2 ]; then
        local confirm_crf0="${confirm_crf2}"
        local confirm_t_bitrate0="${total_bitrate}kbps"
      else
        local confirm_crf0="${confirm_crf1}"
        local confirm_t_bitrate0="${confirm_t_crf}"
      fi
      tdeEcho "${confirm_start}"
      cat <<EOF >&2
${confirm_preset} : ${!confirm_preset0}
${confirm_account} : ${!confirm_account0}
${confirm_player} : ${!confirm_player0}
${confirm_dectype} : ${!confirm_dectype0}
${confirm_crf} : ${confirm_crf0}
${confirm_resize} : ${o_video_width}x${o_video_height}
${confirm_deint} : ${!confirm_deint0}
${confirm_denoise} : ${!confirm_denoise0}
${confirm_audio} : ${confirm_audio0}
${confirm_t_bitrate} : ${confirm_t_bitrate0}
EOF
      tdeEcho ${confirm_last1}
      select item in $confirm_list{1,2}
      do
        [ -z "${item}" ] && tdeEcho ${return_message1} && continue
        confirm_end="${REPLY}"
        break
      done
      if [ "${confirm_end}" -eq 2 ]; then
        tdeEcho "${confirm_last2}"
        echo "r"
        return
      fi
      ;;
  esac
  cat <<EOF
    ${question_type:-2}
    ${site_type:-1}
    ${preset_type:-2}
    ${account_type:-1}
    ${enc_type:-1}
    ${crf_type:-1}
    ${dec_type:-2}
    ${flash_type:-1}
    ${deint_type:-1}
    ${resize_type:-1}
    ${total_time_sec:-0}
    ${o_video_width:-0}
    ${o_video_height:-0}
    ${crf_value:-23}
    ${video_bitrate:-1800}
    ${audio_bitrate:-128}
    ${audio_samplingrate:-1}
    ${samplingrate_value:-44100}
    ${limit_bitrate:-2000}
    ${denoise_type:-1}
EOF
}

tdeFilterAppend()
{
  [ "$1" = "" ] && echo "$2" || echo "$1,$2"
}

# Usage: tdeVideoEncode "${input_video}"
tdeVideoEncode()
{
  tdeEchoS "${video_enc_announce}"

  # variables for video encoding
  local use_ffmpeg=0
  local x264_option=""
  local ffmpeg_option="-y -i $1 -an -pix_fmt yuv420p"
  local ffmpeg_filter=""

  # choose by o_video_height
  if [ "${out_matrix}" != "auto" ]; then
    local out_matrix="${out_matrix}"
  elif [ "${question_info[12]}" -ge 720 ]; then
    local out_matrix="BT.709"
  else
    local out_matrix="BT.601"
  fi
  # use mediainfo for detect input colormatrix
  # if there is no info, choose by the height of input video
  if [ "${in_matrix}" != "auto" ]; then
    local in_matrix="${in_matrix}"
  else
    local in_matrix=""
    local matrix_info=$(${tool_mediainfo} "$1")
    matrix_info=${matrix_info##*'Matrix coefficients'}
    matrix_info=${matrix_info%%A*}
    if $(echo ${matrix_info} | grep -iq 'BT.709'); then
      in_matrix="BT.709"
    elif $(echo ${matrix_info} | grep -iq 'BT.601'); then
      in_matrix="BT.601"
    elif [ ${video_info[4]} -ge 720 ]; then
      in_matrix="BT.709"
    else
      in_matrix="BT.601"
    fi
  fi
  # convert colormatrix if in_matrix != out_matrix

  # define use_ffmpeg
  # use ffmpeg for tdeMuxMode with a still image
  # video_info[1](video bitrate) is 0 if the source file is a still image
  if [ ${video_info[1]} -eq 0 ]; then
    use_ffmpeg=1
    # the lower fps, the smaller file size
    # dont specify too low fps, such as 1fps, or flash player couldnt play it back accurately
    video_info[2]=10
    ffmpeg_option="-f image2 -loop 1 ${ffmpeg_option} -r ${video_info[2]} -t ${question_info[10]}"
  fi
  # question_info[8] is deint_type
  if [ "${question_info[8]}" -eq 2 -o "${video_info[7]}" != "Progressive" ]; then
    use_ffmpeg=1
    ffmpeg_filter=$(tdeFilterAppend "${ffmpeg_filter}" "yadif")
  fi
  # fyi ffmpeg has colormatrix filter while libav doesnt
  if [ "${in_matrix}" != "${out_matrix}" ]; then
    use_ffmpeg=1
    if [ "${in_matrix}" = "BT.601" ]; then
      ffmpeg_filter=$(tdeFilterAppend "${ffmpeg_filter}" "colormatrix=bt601:bt709")
    else
      ffmpeg_filter=$(tdeFilterAppend "${ffmpeg_filter}" "colormatrix=bt709:bt601")
    fi
  fi
  # resize
  [ -z "${resize_method}" ] && resize_method="spline"
  local i_width=${video_info[3]} o_width=${question_info[11]}
  local i_height=${video_info[4]} o_height=${question_info[12]}
  [ "$((${o_width} % 2))" -eq 1 ] && o_width=$((${o_width} + 1))
  [ "$((${o_height} % 2))" -eq 1 ] && o_height=$((${o_height} + 1))
  if [ "${o_width}" -ne ${i_width} -o "${o_height}" -ne ${i_height} ]; then
    ffmpeg_filter=$(tdeFilterAppend "${ffmpeg_filter}" "scale=w=${o_width}:h=${o_height}:flags=${resize_method}")
  fi
  # fps convert
  if [ "${question_info[1]}" -eq 4 ]; then
    out_fps=${twitter_fps}
  elif [ -n "${default_fps}" ]; then
    out_fps=${default_fps}
  else
    out_fps=${video_info[2]}
  fi
  if [ "${video_info[2]}" != "${out_fps}" ]; then
    use_ffmpeg=1
    ffmpeg_filter=$(tdeFilterAppend "${ffmpeg_filter}" "fps=${out_fps}")
  fi
  # add filterchain to ffmpeg_option
  ffmpeg_option="${ffmpeg_option} -sar 1/1 -vf ${ffmpeg_filter}"

  # define other options
  # denoise
  local denoise
  if [ "${question_info[19]}" -eq 2 ] || [ "${question_info[19]}" -eq 1 -a "${question_info[1]}" -ne 1 ]; then
    denoise=1
  else
    denoise=0
  fi
  # round off fps and set ${keyint}
  local keyint_base=$(tdeBc "${out_fps} + 0.5")
  local keyint=$((${keyint_base%.*} * 10))

  case "${use_ffmpeg}" in
    0)
      # define x264 options
      x264_option="$1 ${x264_common[*]} --keyint ${keyint}"
      # question_info[2] is preset_type
      if [ "${question_info[2]}" -lt 3 ]; then
        x264_option="${x264_option} ${x264_anime[*]}"
      elif [ "${question_info[2]}" -lt 6 ]; then
        x264_option="${x264_option} ${x264_film[*]}"
      fi
      if [ "${denoise}" -eq 1 ]; then
        x264_option="${x264_option} ${x264_denoise[*]}"
      fi
      case "${question_info[2]}" in
        1|4)
          x264_pass="${pass_speed}"
          x264_option="${x264_option} ${x264_low[*]}"
          ;;
        2|5)
          x264_pass="${pass_balance}"
          x264_option="${x264_option} ${x264_medium[*]}"
          ;;
        3|6)
          x264_pass="${pass_quality}"
          x264_option="${x264_option} ${x264_high[*]}"
          ;;
        7)
          temp_264="$1"
          return
          ;;
        8)
          x264_pass="${pass_quality}"
          x264_option="${x264_option} ${x264_user[*]}"
          ;;
        9)
          x264_pass=0
          ;;
      esac
      # economy mode for niconico
      [ ${question_info[4]} -eq 2 ] && x264_option="${x264_option} ${x264_economy[*]}"
      # fast decode for niconico
      [ ${question_info[6]} -eq 1 ] && x264_option="${x264_option} ${x264_fast[*]}"
      # youtube or niconico(new)
      [ ${question_info[1]} -ne 1 ] && x264_option="${x264_option} ${x264_youtube[*]}"
      # avoid flash player problems
      case ${question_info[7]} in
        2)
          x264_option="${x264_option} ${x264_flash1[*]}"
          ;;
        3)
          x264_option="${x264_option} ${x264_flash1[*]} ${x264_flash2[*]}"
          ;;
      esac
      if [ "${out_matrix}" = "BT.709" ]; then
        x264_option="${x264_option} --colormatrix bt709"
      else
        x264_option="${x264_option} --colormatrix smpte170m"
      fi
      if [ "${full_range}" = "off" ]; then
        x264_option="${x264_option} --range tv"
      elif [ "${full_range}" = "on" ]; then
        x264_option="${x264_option} --range pc"
      else
        x264_option="${x264_option} --range auto"
      fi
      # slightly reduce video bitrate
      local x264_bitrate=$((${question_info[14]} - ${bitrate_margin}))
      x264_option="${x264_option} -B ${x264_bitrate}"
      # question_info[9] is resize_type
      if [ "${question_info[9]}" -eq 1 -o "${question_info[9]}" -eq 3 ]; then
        local resize_option="--vf resize:width=${question_info[11]},height=${question_info[12]},sar=1:1"
        [ -z "${resize_method}" ] && resize_method="spline"
        x264_option="${x264_option} ${resize_option},method=${resize_method}"
      fi
      # twitter
      if [ "${question_info[1]}" -eq 4 ]; then
        x264_option="${x264_option} ${x264_twitter[*]}"
      fi

      # start video encoding
      case "${x264_pass}" in
        0)
          local h264_size
          local h264_bitrate
          # question_info[5] is crf_type
          if [ "${question_info[5]}" -ne 2 ]; then
            tdeEchoS "${pass_announce10}"
            local x264_crf="--crf ${question_info[13]}"
            ${tool_x264} ${x264_option} ${x264_crf} -o "${temp_264}"
            if [ -s "${temp_264}" ]; then
              # question_info[14] is video_bitrate
              h264_size=$(tdeMediaInfo -g "FileSize" "${temp_264}")
              h264_bitrate=$((${h264_size} * 8 / 1024 / ${question_info[10]}))
              if [ "${h264_bitrate}" -le ${question_info[14]} ]; then
                if [ "${question_info[1]}" -eq 2 ]; then
                  if [ "${h264_bitrate}" -ge ${bitrate_nico_new_threshold} ]; then
                    tdeEchoS "${video_enc_success}"
                    return
                  else
                    x264_option="${x264_option%*--keyint *} --keyint ${keyint_base%.*} -${x264_option#*--keyint *-}"
                  fi
                else
                  tdeEchoS "${video_enc_success}"
                  return
                fi
              fi
            else
              tdeEchoS $video_enc_error{1,2}
              tdeError
            fi
          fi
          tdeEchoS "${pass_announce1}"
          tdeEchoS "${pass_announce2}"
          ${tool_x264} ${x264_option} -p 1 -o /dev/null
          tdeEchoS "${pass_announce3}"
          ${tool_x264} ${x264_option} -p 3 -o "${temp_264}"
          # auto 3pass
          if [ -s "${temp_264}" ]; then
            h264_size=$(tdeMediaInfo -g "FileSize" "${temp_264}")
            h264_bitrate=$((${h264_size} * 8 / 1024 / ${question_info[10]}))
            if [ "${h264_bitrate}" -le ${question_info[14]} ]; then
              tdeEchoS "${video_enc_success}"
              return
            fi
          fi
          tdeEcho $pass_announce{5,6}
          tdeEchoS "${pass_announce6}"
          ${tool_x264} ${x264_option} -p 2 -o "${temp_264}"
          ;;
        1)
          tdeEchoS "${pass_announce7}"
          tdeEchoS "${pass_announce2}"
          ${tool_x264} ${x264_option} -o "${temp_264}"
          ;;
        2)
          tdeEchoS "${pass_announce8}"
          tdeEchoS "${pass_announce2}"
          ${tool_x264} ${x264_option} -p 1 -o /dev/null
          tdeEchoS "${pass_announce3}"
          ${tool_x264} ${x264_option} -p 2 -o "${temp_264}"
          ;;
        3)
          tdeEchoS "${pass_announce9}"
          tdeEchoS "${pass_announce2}"
          ${tool_x264} ${x264_option} -p 1 -o /dev/null
          tdeEchoS "${pass_announce3}"
          ${tool_x264} ${x264_option} -p 3 -o /dev/null
          tdeEchoS "${pass_announce4}"
          ${tool_x264} ${x264_option} -p 2 -o "${temp_264}"
          ;;
      esac
      if [ -s "${temp_264}" ]; then
        tdeEchoS "${video_enc_success}"
      else
        tdeEchoS $video_enc_error{1,2}
        tdeError
      fi
      ;;
    1)
      local libx264_option="-vcodec libx264 -passlogfile ${temp_dir}/x264.log -x264opts"
      # define libx264 options
      libx264_option="${libx264_option} sar=1/1:keyint=${keyint}"
      # colormatrix
      if [ "${out_matrix}" = "BT.709" ]; then
        libx264_option="${libx264_option}:colormatrix=bt709"
      else
        libx264_option="${libx264_option}:colormatrix=smpte170m"
      fi
      for item in ${ffmpeg_common[@]}
      do
        libx264_option="${libx264_option}:${item}"
      done
      # question_info[2] is preset_type
      if [ "${question_info[2]}" -lt 3 ]; then
        for item in ${ffmpeg_anime[@]}
        do
          libx264_option="${libx264_option}:${item}"
        done
      elif [ "${question_info[2]}" -lt 6 ]; then
        for item in ${ffmpeg_film[@]}
        do
          libx264_option="${libx264_option}:${item}"
        done
      fi
      if [ "${denoise}" -eq 1 ]; then
        for item in ${ffmpeg_denoise[@]}
        do
          libx264_option="${libx264_option}:${item}"
        done
      fi
      case "${question_info[2]}" in
        1|4)
          x264_pass="${pass_speed}"
          for item in ${ffmpeg_low[@]}
          do
            libx264_option="${libx264_option}:${item}"
          done
          ;;
        2|5)
          x264_pass="${pass_balance}"
          for item in ${ffmpeg_medium[@]}
          do
            libx264_option="${libx264_option}:${item}"
          done
          ;;
        3|6)
          x264_pass="${pass_quality}"
          for item in ${ffmpeg_high[@]}
          do
            libx264_option="${libx264_option}:${item}"
          done
          ;;
        7)
          temp_264="$1"
          return
          ;;
        8)
          x264_pass="${pass_quality}"
          for item in ${ffmpeg_user[@]}
          do
            libx264_option="${libx264_option}:${item}"
          done
          ;;
        9)
          x264_pass=0
          ;;
      esac
      # economy mode for niconico
      if [ ${question_info[4]} -eq 2 ]; then
        for item in ${ffmpeg_economy[@]}
        do
          libx264_option="${libx264_option}:${item}"
        done
      fi
      # fast decode for niconico
      if [ ${question_info[6]} -eq 1 ]; then
        for item in ${ffmpeg_fast[@]}
        do
          libx264_option="${libx264_option}:${item}"
        done
      fi
      # youtube or niconico(new)
      if [ ${question_info[1]} -ne 1 ]; then
        for item in ${ffmpeg_youtube[@]}
        do
          libx264_option="${libx264_option}:${item}"
        done
      fi
      # avoid flash player problems
      case ${question_info[7]} in
        2)
          ffmpeg_option="${ffmpeg_option} -flags -loop"
          ;;
        3)
          ffmpeg_option="${ffmpeg_option} -flags -loop"
          libx264_option="${libx264_option}:weightp=0"
          ;;
      esac
      # slightly reduce video bitrate
      local libx264_bitrate=$((${question_info[14]} - ${bitrate_margin}))

      # define ffmpeg options
      local i_width=${video_info[3]} o_width=${question_info[11]}
      local i_height=${video_info[4]} o_height=${question_info[12]}
      [ "$((${o_width} % 2))" -eq 1 ] && o_width=$((${o_width} + 1))
      [ "$((${o_height} % 2))" -eq 1 ] && o_height=$((${o_height} + 1))
      if [ "${o_width}" -ne "${i_width}" -o "${o_height}" -ne "${i_height}" ]; then
        ffmpeg_option="${ffmpeg_option} -s ${o_width}x${o_height}"
        [ -z "${resize_method}" ] && resize_method="spline"
        ffmpeg_option="${ffmpeg_option} -sws_flags ${resize_method}"
      fi
      # twitter
      if [ "${question_info[1]}" -eq 4 ]; then
        ffmpeg_option="${ffmpeg_option} ${ffmpeg_twitter[*]}"
      fi

      # start video encoding
      case "${x264_pass}" in
        0)
          local h264_size
          local h264_bitrate
          # question_info[5] is crf_type
          if [ "${question_info[5]}" -ne 2 ]; then
            tdeEchoS "${pass_announce10}"
            local libx264_crf=":crf=${question_info[13]}"
            ${tool_ffmpeg} ${ffmpeg_option} ${libx264_option}${libx264_crf} "${temp_264}"
            if [ -s "${temp_264}" ]; then
              # question_info[14] is video_bitrate
              h264_size=$(tdeMediaInfo -g "FileSize" "${temp_264}")
              h264_bitrate=$((${h264_size} * 8 / 1024 / ${question_info[10]}))
              if [ "${h264_bitrate}" -le ${question_info[14]} ]; then
                if [ "${question_info[1]}" -eq 2 ]; then
                  if [ "${h264_bitrate}" -ge ${bitrate_nico_new_threshold} ]; then
                    tdeEchoS "${video_enc_success}"
                    return
                  else
                    libx264_option="${libx264_option%*keyint=*}keyint=${keyint_base%.*}:${libx264_option#*keyint=*:}"
                  fi
                else
                  tdeEchoS "${video_enc_success}"
                  return
                fi
              fi
            else
              tdeEchoS $video_enc_error{1,2}
              tdeError
            fi
          fi
          tdeEchoS "${pass_announce1}"
          tdeEchoS "${pass_announce2}"
          ffmpeg_option="${ffmpeg_option} -b:v ${libx264_bitrate}k"
          ${tool_ffmpeg} ${ffmpeg_option} ${libx264_option} -pass 1 "${temp_264}"
          tdeEchoS "${pass_announce3}"
          ${tool_ffmpeg} ${ffmpeg_option} ${libx264_option} -pass 3 "${temp_264}"
          # auto 3pass
          if [ -s "${temp_264}" ]; then
            h264_size=$(tdeMediaInfo -g "FileSize" "${temp_264}")
            h264_bitrate=$((${h264_size} * 8 / 1024 / ${question_info[10]}))
            if [ "${h264_bitrate}" -le ${question_info[14]} ]; then
              tdeEchoS "${video_enc_success}"
              return
            fi
          fi
          tdeEcho $pass_announce{5,6}
          tdeEchoS "${pass_announce6}"
          ${tool_ffmpeg} ${ffmpeg_option} ${libx264_option} -pass 2 "${temp_264}"
          ;;
        1)
          tdeEchoS "${pass_announce7}"
          tdeEchoS "${pass_announce2}"
          ffmpeg_option="${ffmpeg_option} -b:v ${libx264_bitrate}k"
          ${tool_ffmpeg} ${ffmpeg_option} ${libx264_option} "${temp_264}"
          ;;
        2)
          tdeEchoS "${pass_announce8}"
          tdeEchoS "${pass_announce2}"
          ffmpeg_option="${ffmpeg_option} -b:v ${libx264_bitrate}k"
          ${tool_ffmpeg} ${ffmpeg_option} ${libx264_option} -pass 1 "${temp_264}"
          tdeEchoS "${pass_announce3}"
          ${tool_ffmpeg} ${ffmpeg_option} ${libx264_option} -pass 2 "${temp_264}"
          ;;
        3)
          tdeEchoS "${pass_announce9}"
          tdeEchoS "${pass_announce2}"
          ffmpeg_option="${ffmpeg_option} -b:v ${libx264_bitrate}k"
          ${tool_ffmpeg} ${ffmpeg_option} ${libx264_option} -pass 1 "${temp_264}"
          tdeEchoS "${pass_announce3}"
          ${tool_ffmpeg} ${ffmpeg_option} ${libx264_option} -pass 3 "${temp_264}"
          tdeEchoS "${pass_announce4}"
          ${tool_ffmpeg} ${ffmpeg_option} ${libx264_option} -pass 2 "${temp_264}"
          ;;
      esac
      if [ -s "${temp_264}" ]; then
        tdeEchoS "${video_enc_success}"
      else
        tdeEchoS $video_enc_error{1,2}
        tdeError
      fi
      ;;
  esac
}

# Usage: tdeAudioEncode "${input_audio}"
tdeAudioEncode()
{
  tdeEchoS "${audio_enc_announce}"

  # variables for audio encoder
  local aac_option
  local ffmpeg_aac="-vn -y -acodec aac -strict -2"
  if [ "${audio_info[3]}" -gt 5 ]; then
    pcm_c_layout="5.1"
  elif [ "${audio_info[3]}" -eq 1 ]; then
    pcm_c_layout="mono"
  else
    pcm_c_layout="stereo"
  fi
  local ffmpeg_pcm="-vn -y -acodec pcm_s16le -channel_layout ${pcm_c_layout}"

  # silent
  if [ "${question_info[15]}" -eq 0 -o "${audio_info[0]}" -eq 0 ]; then
    ffmpeg_pcm="${ffmpeg_pcm} -ar 44100 -f s16le"
    ffmpeg_aac="-profile aac_he ${ffmpeg_aac} -b:a 48k"
    ${tool_ffmpeg} ${ffmpeg_pcm} -i /dev/zero ${ffmpeg_aac} -t 1 "${temp_m4a}"
    return
  fi

  # define audio options
  local a_bitrate="${question_info[15]}"
  # define aac profile
  local aac_profile
  local audio_surround
  [ "${audio_info[3]}" -le 2 ] && audio_surround=1 || audio_surround=2
  if [ "${a_bitrate}" -le $((32 * ${audio_surround})) ]; then
    [ "${audio_info[3]}" -eq 2 ] && aac_profile="hev2" || aac_profile="he"
  elif [ "${a_bitrate}" -le $((64 * ${audio_surround})) ]; then
    aac_profile="he"
  else
    aac_profile="lc"
  fi
  if $(echo ${tool_aacEnc} | grep -iq 'afconvert'); then
    local apple_profile
    if [ "${aac_profile}" = "hev2" ]; then
      apple_profile="aacp"
    elif [ "${aac_profile}" = "he" ]; then
      apple_profile="aach"
    else
      apple_profile="aac"
    fi
    aac_option="-v -b ${a_bitrate}000 -s 2 -f m4af -d ${apple_profile}"
    if [ "${pcm_c_layout}" = "5.1" ]; then
      aac_option="${aac_option} -l AAC_5_1"
    fi
  elif $(echo ${tool_aacEnc} | grep -iq 'neroAacEnc'); then
    aac_option="-2pass -br ${a_bitrate}000"
  else
    local ffmpeg_profile
    if [ "${aac_profile}" = "hev2" ]; then
      ffmpeg_profile="aac_he_v2"
    elif [ "${aac_profile}" = "he" ]; then
      ffmpeg_profile="aac_he"
    else
      ffmpeg_profile="aac_low"
    fi
    aac_option="-profile ${ffmpeg_profile} ${ffmpeg_aac} -b:a ${a_bitrate}k"
    if [ "${a_bitrate}" -lt $((128 * ${audio_surround})) ]; then
      cutoff_value=16000
    elif [ "${a_bitrate}" -lt $((224 * ${audio_surround})) ]; then
      cutoff_value=18000
    else
      cutoff_value=20000
    fi
    aac_option="${aac_option} -cutoff ${cutoff_value}"
  fi
  [ "${question_info[17]}" -ne 0 ] && local ffmpeg_samplingrate="-ar ${question_info[17]}"

  # skip audio encoding if the audio format is AAC and the bitrate is low enough
  local audio_codec=$(tdeMediaInfo -a Format "%1")
  if $(echo "${audio_codec}" | grep -iq 'AAC'); then
    local h264_size=$(tdeMediaInfo -g "FileSize" "${temp_264}")
    local h264_bitrate=$((${h264_size} * 8 / 1024 / ${question_info[10]}))
    local a_limit_bitrate=$((${question_info[18]} - ${h264_bitrate}))
    if [ "${audio_info[1]}" -lt ${a_limit_bitrate} ]; then
      temp_m4a="$1"
      return
    fi
  fi

  # start audio encoding
  if $(echo ${tool_aacEnc} | grep -iq 'afconvert'); then
    # afconvert accepts some audio formats
    if [ -n "${audio_ext}" -a "${audio_info[2]}" -le 48000 ]; then
      ${tool_aacEnc} ${aac_option} "$1" "${temp_m4a}"
    else
      tdeEchoS ${audio_wav_announce}
      ${tool_ffmpeg} -loglevel quiet -i "$1" ${ffmpeg_pcm} ${ffmpeg_samplingrate} "${temp_wav}"
      ${tool_aacEnc} ${aac_option} "${temp_wav}" "${temp_m4a}"
    fi
  elif $(echo ${tool_aacEnc} | grep -iq 'neroAacEnc'); then
    # neroAacEnc accepts WAVE
    if [ "${audio_ext}" = "wav" -a "${audio_info[2]}" -le 48000 ]; then
      ${tool_aacEnc} ${aac_option} -if "$1" -of "${temp_m4a}"
    else
      tdeEchoS ${audio_wav_announce}
      ${tool_ffmpeg} -loglevel quiet -i "$1" ${ffmpeg_pcm} ${ffmpeg_samplingrate} "${temp_wav}"
      ${tool_aacEnc} ${aac_option} -if "${temp_wav}" -of "${temp_m4a}"
    fi
  else
    # ffmpeg accepts a lot of audio formats
    ${tool_aacEnc} -i "$1" ${aac_option} ${ffmpeg_samplingrate} "${temp_m4a}"
  fi

  # check if audio encoding succeeded
  if [ -s "${temp_m4a}" ]; then
    tdeEchoS "${audio_enc_success}"
  else
    tdeEchoS $audio_enc_error{1,2}
    tdeError
  fi
}

# Usage: tdeMP4
tdeMP4()
{
  tdeEchoS "${mp4_announce}"

  # start muxing
  if [ -n "${tool_MP4Box}" ]; then
    [ "${question_info[2]}" -eq 7 ] || mp4_fps="-fps ${out_fps}"
    ${tool_MP4Box} ${mp4_fps} -add "${temp_264}#video" -add "${temp_m4a}#audio" -new "${temp_mp4}"
  else
    if [ "${question_info[2]}" -eq 7 ]; then
      ${tool_ffmpeg} -loglevel quiet -i "${temp_264}" -an -vcodec copy "${temp_dir}/video.h264"
      temp_264="${temp_dir}/video.h264"
    else
      mp4_fps="-r ${out_fps}"
    fi
    ${tool_ffmpeg} ${mp4_fps} -i "${temp_264}" -i "${temp_m4a}" -vcodec copy -acodec copy "${temp_mp4}"
  fi

  # backup
  [ -e "${output_mp4name}" ] && mv "${output_mp4name}" "${mp4_dir}/old.mp4"
  mv "${temp_mp4}" "${output_mp4name}" >/dev/null 2>&1

  # check if muxing succeeded
  if [ -s "${output_mp4name}" ]; then
    tdeEchoS "${mp4_success}"
  else
    tdeEchoS $mp4_error{1,2}
    tdeError
  fi

  #TODO: check file size
  tdeShowInfo "${output_mp4name}"
}

# Usage: tdeEnc2mp4 "${input_video}" "${input_audio}"
tdeEnc2mp4()
{
  while :
  do
    question_info=($(tdeAskQuestion))
    [ "${question_info}" = "r" ] && continue
    [ "${#question_info[*]}" -eq 20 ] && break || exit
  done
  tdeVideoEncode "$1"
  tdeAudioEncode "$2"
  tdeMP4
}

# Usage: tdeSerialMode "${input_video}"
tdeSerialMode()
{
  tdeEcho $analyze_announce{1,2}
  tdeShowInfo "$1"
  video_info=($(tdeVideoInfo "$1"))
  audio_info=($(tdeAudioInfo "$1"))
  if [ "${video_info[3]}" -eq 0 ]; then
    tdeEcho $analyze_error{1..3}
    tdeError
  fi
  tdeEnc2mp4 "$1" "$1"
}

# Usage: tdeMuxMode "${input_video}" "${input_audio}"
tdeMuxMode()
{
  tdeEcho $analyze_announce{1,2}
  tdeShowInfo "$1" "$2"
  video_info=($(tdeVideoInfo "$1"))
  audio_info=($(tdeAudioInfo "$2"))
  [ "${video_info[0]}" -eq 0 ] && video_info[0]="${audio_info[0]}"
  if [ "${video_info[3]}" -eq 0 -o "${audio_info[0]}" -eq 0 ]; then
    tdeEcho $analyze_error{1..3}
    tdeError
  fi
  tdeEnc2mp4 "$1" "$2"
}

tdeToolUpdate()
{
  tdeEcho $auto_install_start{1,2}
  if [ "${os}" = "Mac" ]; then
    # for mac
    [ -d "../Archives" ] || mkdir -p "../Archives" >/dev/null 2>&1
    [ -s "../Archives/Mac.zip" ] || curl -o ../Archives/Mac.zip -L "https://raw.githubusercontent.com/tdenc/TDEnc2/master/Archives/Mac.zip"
    if [ "$?" -eq 0 ]; then
      tdeEchoS "${auto_install_end}"
    else
      tdeEcho $auto_install_error{1,2}
      tdeError
    fi
    unzip -qjo ../Archives/Mac.zip 2>/dev/null
    # TODO: for linux and windows
  fi
  chmod +x ${tool_ffmpeg} ${tool_x264} ${tool_MP4Box} ${tool_mediainfo}
}

# }}}

### Start TDEnc2 ### {{{
trap "tdeHandler" INT
# os
# might run on other platforms, i dont care though :p
if [ $(uname) = "Darwin" ]; then
  os="Mac"
elif [ $(uname) = "Linux" ]; then
  os="Linux"
elif [ $(uname -o) = "Cygwin" -o $(uname -o) = "Msys" ]; then
  os="Windows"
else
  tdeEcho $platform_start{1..3}
  select item in $platform_list{1,2}
  do
    [ -z "${item}" ] && tdeEcho ${return_message1} && continue
    platform="${REPLY}"
    break
  done
  case "${platform}" in
    2)
      tdeError
      ;;
  esac
fi

# print version info
clear
echo "${color_green}+${color_blue}---------------------------${color_green}+"
echo "${color_blue}| ${color_purple}TDEnc2 for Bash (ver${current_version}) ${color_blue}|"
echo "${color_green}+${color_blue}---------------------------${color_green}+${color_reset}"

# check updates and auto-update
latest_version=$(curl -s "https://raw.githubusercontent.com/tdenc/TDEnc2/master/tool/current_version")
[ -z "${latest_version}" ] && latest_version=${current_version}
need_update=$(tdeBc "${latest_version} > ${current_version}")
if [ "${need_update}" -eq 1 ]; then
  tdeEcho $update_start{1..3}
  cat <<EOF
 ${update_start4}
 ${short_line}
$(curl -s "https://raw.githubusercontent.com/tdenc/TDEnc2/master/tool/ChangeLog")
 ${short_line}

EOF
  select item in $update_list{1..3}
  do
    [ -z "${item}" ] && tdeEcho ${return_message1} && continue
    update="${REPLY}"
    break
  done
  case "${update}" in
    1)
      # backup old user settings
      [ -d "../setting/backup" ] || mkdir -p "../setting/backup" >/dev/null 2>&1
      cp -fpR ../setting/*.conf ../setting/backup/
      curl -o master.zip -L "https://github.com/tdenc/TDEnc2/archive/master.zip"
      unzip -qo master.zip 2>/dev/null
      cp -fpR TDEnc2-master/* ../
      chmod +x TDEnc2.sh ../TDEnc2.app/Contents/MacOS/droplet
      rm -rf TDEnc2-master >/dev/null 2>&1
      tdeToolUpdate
      tdeEchoS "${update_end}"
      ./TDEnc2.sh "$@"
      exit
      ;;
    3)
      echo "${latest_version}" > "${ver_txt}"
      ;;
  esac
fi

# auto-install tools
if [ ! \( -e ${tool_ffmpeg} -a -e ${tool_x264} -a -e ${tool_mediainfo} \) ]; then
  tdeToolUpdate
fi

# check tools, `which ${tool}` if necessary
./${tool_ffmpeg} -h >/dev/null 2>&1
if [ "$?" -eq 0 ]; then
  tool_ffmpeg="./${tool_ffmpeg}"
else
  tool_ffmpeg=$(which ${tool_ffmpeg} 2>/dev/null)
  [ -z "${tool_ffmpeg}" ] && tdeEcho $tool_error{1,2} && tdeError
fi
./${tool_x264} -h >/dev/null 2>&1
if [ "$?" -eq 0 ]; then
  tool_x264="./${tool_x264}"
else
  tool_x264=$(which ${tool_x264} 2>/dev/null)
  [ -z "${tool_x264}" ] && tdeEcho $tool_error{1,2} && tdeError
fi
tool_x264_version=$(${tool_x264} --version | head -n1)
if $(echo "${tool_x264_version}" | grep -ivq "${current_x264_version}"); then
  rm ${tool_x264}
  tdeToolUpdate
fi
./${tool_MP4Box} -h >/dev/null 2>&1
if [ "$?" -eq 0 ]; then
  tool_MP4Box="./${tool_MP4Box}"
else
  tool_MP4Box=$(which ${tool_MP4Box} 2>/dev/null)
fi
mediainfo_check=($(./${tool_mediainfo} --version 2>/dev/null))
if [ "${mediainfo_check}" = "MediaInfo" ]; then
  tool_mediainfo="./${tool_mediainfo}"
else
  tool_mediainfo=$(which ${tool_mediainfo} 2>/dev/null)
  [ -z "${tool_mediainfo}" ] && tdeEcho $tool_error{1,2} && tdeError
fi
if [ "${os}" = "Mac" ]; then
  if [ "${mac_aacEnc}" = "afconvert" ]; then
    tool_aacEnc=$(which afconvert 2>/dev/null)
  else
    ./${mac_aacEnc} -h >/dev/null 2>&1
    if [ "$?" -eq 0 ]; then
      tool_aacEnc="./${mac_aacEnc}"
    else
      tool_aacEnc=$(which ${mac_aacEnc} 2>/dev/null)
    fi
  fi
elif [ "${os}" = "Linux" ]; then
  ./${linux_aacEnc} -help >/dev/null 2>&1
  if [ "$?" -eq 0 ]; then
    tool_aacEnc="./${linux_aacEnc}"
  else
    tool_aacEnc=$(which ${linux_aacEnc} 2>/dev/null)
  fi
elif [ "${os}" = "Windows" ]; then
  ./${win_aacEnc} -help >/dev/null 2>&1
  if [ "$?" -eq 0 ]; then
    tool_aacEnc="./${win_aacEnc}"
  else
    tool_aacEnc=$(which ${win_aacEnc} 2>/dev/null)
  fi
fi
if [ -z "${tool_aacEnc}" ]; then
  [ "${os}" = "Mac" ] && tdeEcho $tool_aac_warning{1,3} || tdeEcho $tool_aac_warning{2,3}
  tool_aacEnc=${tool_ffmpeg}
fi

# check arguments, and go to main proccess
# use symbolic links to avoid white space problems
case "$#" in
  0)
    tdeEcho "${doubleclick_alert1}" "${doubleclick_alert2}"
    tdeError
    ;;
  1)
    tdeEcho "${one_movie_announce}"
    tdenc_mode=1
    source_video="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
    output_basename="${source_video##*/}"
    output_mp4name="${mp4_dir}/${output_basename%.*}.mp4"
    input_video="${temp_dir}/source.${1##*.}"
    ln -s "${source_video}" "${input_video}"
    tdeSerialMode "${input_video}"
    tdeEcho $dere_message{1,2}
    tdeSuccess
    ;;
  2)
    first_ext=$(echo "${1##*.}" | tr [:upper:] [:lower:])
    second_ext=$(echo "${2##*.}" | tr [:upper:] [:lower:])
    audio_array=()
    audio_pattern="wave?|mp3|aif+"
    if [[ ${first_ext} =~ ${audio_pattern} ]]; then
      audio_array=("${audio_array[@]}" "$1")
      audio_ext="${first_ext}"
      shift
    fi
    if [[ ${second_ext} =~ ${audio_pattern} ]]; then
      audio_array=("${audio_array[@]}" "$2")
      audio_ext="${second_ext}"
    fi
    case "${#audio_array[*]}" in
      0)
        tdeEcho "${sequence_announce}"
        tdenc_mode=3
        for item in "$@"
        do
          source_video="$(cd "$(dirname "${item}")" && pwd)/$(basename "${item}")"
          output_basename="${source_video##*/}"
          output_mp4name="${mp4_dir}/${output_basename%.*}.mp4"
          input_video="${temp_dir}/source.${item##*.}"
          ln -s "${source_video}" "${input_video}"
          tdeSerialMode "${input_video}"
          rm "${input_video}"
        done
        tdeEcho $sequence_end{1..3}
        tdeSuccess
        ;;
      1)
        tdeEcho "${mux_announce}"
        tdenc_mode=2
        source_video="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
        source_audio="$(cd "$(dirname "${audio_array}")" && pwd)/$(basename "${audio_array}")"
        output_basename="${source_video##*/}"
        output_mp4name="${mp4_dir}/${output_basename%.*}.mp4"
        video_ext=$(echo "${1##*.}" | tr [:upper:] [:lower:])
        input_video="${temp_dir}/source.${video_ext}"
        input_audio="${temp_dir}/source.${audio_ext}"
        ln -s "${source_video}" "${input_video}"
        ln -s "${source_audio}" "${input_audio}"
        tdeMuxMode "${input_video}" "${input_audio}"
        tdeEcho $dere_message{1,2}
        tdeSuccess
        ;;
      2)
        tdeEcho "${muxmode_error}"
        tdeError
        ;;
    esac
    ;;
  *)
    tdeEcho "${sequence_announce}"
    tdenc_mode=3
    for item in "$@"
    do
      source_video="$(cd "$(dirname "${item}")" && pwd)/$(basename "${item}")"
      output_basename="${source_video##*/}"
      output_mp4name="${mp4_dir}/${output_basename%.*}.mp4"
      input_video="${temp_dir}/source.${item##*.}"
      ln -s "${source_video}" "${input_video}"
      tdeSerialMode "${input_video}"
      rm "${input_video}"
    done
    tdeEcho $sequence_end{1..3}
    tdeSuccess
    ;;
esac

# }}}

# end of file. hehehe.

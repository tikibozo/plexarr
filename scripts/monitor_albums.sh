#!/bin/bash

# some overrides use: ./monitor_albums -n "Artist"
apiKeyArg="apikey"
baseUrlArg="http://yourserver:8686"
monitored="false"

helpText="
# Usage:\n
#\n
# ./monitor_albums.sh -k 'apiKey' -b 'http://host:port' [-m|u|A|h][-n 'artist name'][-i artistId]\n
#\n
# Required Options:\n
# -k                  Your Lidarr API Key (defaults to \$apiKey env variable)\n
# -b                  Your Lidarr instance URL (defaults to \$baseUrl env variable)\n
# -m|u                [Un]Monitor the found albums\n
#\n
# Artist Options:\n
# -A                  Unmonitors all <albumType> from all artists\n
# -n 'artist name'    Unmonitors all <albumType> from specified artist by name\n
# -i artistId         Unmonitors all <albumType> from specified artist by ID\n
#\n
# -h                  Help text\n
"

ask() {
	conYn='y'
	return 
  if [[ ! $1 ]]; then
    error "You must pass a question to ask!"
  else
    question=$1
    input=${2:="y/n"}
    echo -e "\n\e[1;34m$question\e[0m" && echo "[$input] > "
    [[ $3 ]] && read $3
  fi
}

[[ ! $* ]] && echo -e $helpText && exit 1

while getopts k:b:t:i:n:Ahum flag; do
  case ${flag} in
    k)
      apiKeyArg=${OPTARG};;
    b)
      baseUrlArg=${OPTARG};;
    u)
      monitored=false;;
    m)
      monitored=true;;
    i)
      artistId=${OPTARG};;
    n)
      artistName=${OPTARG};;
    A)
      all=true;;
    h)
      echo -e $helpText;
      exit 0;;

    \?)
      echo "Invalid option: -$OPTARG" >&2;
      exit 1;;
    :)
      echo "Option -$OPTARG requires an argument." >&2;
      exit 1;;
  esac
done

apiKey="${apiKeyArg:=$apiKey}"
baseUrl="${baseUrlArg:=$baseUrl}/api/v1"

[[ ! $apiKey ]] && echo "No api key specified. Use -k or 'export apiKey=yourkeyhere'." && exit 1
[[ $baseUrl == "/api/v1" ]] && echo "Lidarr URL not specified. Use -b or 'export baseUrl=http://host:port'." && exit 1
[[ ! $monitored ]] && echo "Must specify -m monitor or -u to unmonitor!" && exit 1

if [[ $artistName != "" ]]; then
  echo "Looking for artist $artistName"
  artists=`curl "$baseUrl/artist?apiKey=$apiKey" -s`
#  echo $artists
  artistId=`echo $artists | jq --arg artistName "$artistName" '
    .[]
    | select(.artistName == $artistName)
    | .id'`
  if [[ $artistId != "" ]]; then
    echo "Artist found."
  else
    echo "Artist not found."
    exit 1
  fi

elif [[ $artistId != "" ]]; then
  echo "Looking artist by id $artistId"
  artist=`curl "$baseUrl/artist/$artistId?apiKey=$apiKey" -s`
  artistName=`echo $artist | jq .artistName`

  if [[ $artistName != null ]]; then
    echo "Artist found: $artistName"
  else
    echo "Artist not found."
    exit 1
  fi
fi

[[ $all != true ]] && query="&artistId=$artistId" || query=""
[[ $all == true ]] && echo "Fetching all artists..."

albums=`curl "$baseUrl/album?apiKey=$apiKey$query" -s`
#foundAlbums=`echo $albums | jq --arg albumType "$albumType" '[.[] | select(.albumType | contains($albumType)) | { title: .title, id: .id}]'`
foundAlbums=`echo $albums | jq '[.[] | select(. != null) | { title: .title, id: .id}]'`
albumNames=`echo $foundAlbums | jq '.[] | .title'`
albumIds=`echo $foundAlbums | jq '[.[] | .id]'`

[[ $monitored == true ]] && monitorString=monitor || monitorString=unmonitor

ask_artist() {
  while true; do
    ask "Are you sure you want to $monitorString the following $albumType(s) from \"$artistName\"?:\n$albumNames" "N/y" conYn
    case $conYn in
      [yY]* )
        cont;
        break;;
      * )
        echo "Cancelled";
        exit 0;;
    esac
  done
}

ask_all() {
  while true; do
    ask "Are you sure you want to $monitorString $albumType(s) from all artists?:\n$albumNames" "N/y" conYn
    case $conYn in
      [yY]* )
        cont;
        break;;
      * )
        echo "Cancelled";
        exit 0;;
    esac
  done
}

generate_put_data() {
cat <<EOF
{
  "albumIds": $albumIds,
  "monitored": $monitored
}
EOF
}

cont() {
  curl -X PUT -H "Content-Type: application/json" -d "$(generate_put_data)" "$baseUrl/album/monitor?apiKey=$apiKey" --silent > /dev/null
}

# No found albums
[[ ${#foundAlbums} -lt 3 ]] && echo "No $albumType(s) found for $artistName" && exit 1

# Confirm operation
[[ $all == true ]] && ask_all || ask_artist

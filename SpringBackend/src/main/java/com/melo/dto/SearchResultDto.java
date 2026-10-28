package com.melo.dto;

public class SearchResultDto {
    private String type;
    private String id;
    private String title;
    private String artist;
    private String artistId;
    private String artistImage;
    private String image;
    private String duration;
    private int nbFan;
    private String previewUrl;
    private int rank;
    private String genre;
    private String releaseDate;
    private String videoId;

    public SearchResultDto() {}

    public SearchResultDto(String type, String id, String title, String artist, String image, String duration, int nbFan, String previewUrl) {
        this.type = type;
        this.id = id;
        this.title = title;
        this.artist = artist;
        this.artistId = "";
        this.artistImage = "";
        this.image = image;
        this.duration = duration;
        this.nbFan = nbFan;
        this.previewUrl = previewUrl;
        this.rank = 0;
        this.genre = "";
    }

    public SearchResultDto(String type, String id, String title, String artist, String image, String duration, int nbFan, String previewUrl, int rank) {
        this.type = type;
        this.id = id;
        this.title = title;
        this.artist = artist;
        this.artistId = "";
        this.artistImage = "";
        this.image = image;
        this.duration = duration;
        this.nbFan = nbFan;
        this.previewUrl = previewUrl;
        this.rank = rank;
        this.genre = "";
    }

    public String getType() { return type; }
    public void setType(String type) { this.type = type; }
    public String getId() { return id; }
    public void setId(String id) { this.id = id; }
    public String getTitle() { return title; }
    public void setTitle(String title) { this.title = title; }
    public String getName() { return title; }
    public String getArtist() { return artist; }
    public void setArtist(String artist) { this.artist = artist; }
    public String getArtistId() { return artistId; }
    public void setArtistId(String artistId) { this.artistId = artistId; }
    public String getArtistImage() { return artistImage; }
    public void setArtistImage(String artistImage) { this.artistImage = artistImage; }
    public String getImage() { return image; }
    public void setImage(String image) { this.image = image; }
    public String getDuration() { return duration; }
    public void setDuration(String duration) { this.duration = duration; }
    public int getNbFan() { return nbFan; }
    public void setNbFan(int nbFan) { this.nbFan = nbFan; }
    public String getPreviewUrl() { return previewUrl; }
    public void setPreviewUrl(String previewUrl) { this.previewUrl = previewUrl; }
    public int getRank() { return rank; }
    public void setRank(int rank) { this.rank = rank; }
    public String getGenre() { return genre; }
    public void setGenre(String genre) { this.genre = genre; }
    public String getReleaseDate() { return releaseDate; }
    public void setReleaseDate(String releaseDate) { this.releaseDate = releaseDate; }
    public String getVideoId() { return videoId; }
    public void setVideoId(String videoId) { this.videoId = videoId; }
}

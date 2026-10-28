package com.melo.dto;

public class YouTubeResultDto {
    private String videoId;
    private String title;
    private String artist;
    private int durationSeconds;

    public YouTubeResultDto() {}

    public YouTubeResultDto(String videoId, String title, String artist, int durationSeconds) {
        this.videoId = videoId;
        this.title = title;
        this.artist = artist;
        this.durationSeconds = durationSeconds;
    }

    public String getVideoId() { return videoId; }
    public void setVideoId(String videoId) { this.videoId = videoId; }
    public String getTitle() { return title; }
    public void setTitle(String title) { this.title = title; }
    public String getArtist() { return artist; }
    public void setArtist(String artist) { this.artist = artist; }
    public int getDurationSeconds() { return durationSeconds; }
    public void setDurationSeconds(int durationSeconds) { this.durationSeconds = durationSeconds; }
}

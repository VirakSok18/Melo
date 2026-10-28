package com.melo.dto;

import java.util.List;

public class ArtistDto {
    private String id;
    private String name;
    private String image;
    private List<String> genres;
    private int popularity;

    public ArtistDto() {}

    public ArtistDto(String id, String name, String image, List<String> genres, int popularity) {
        this.id = id;
        this.name = name;
        this.image = image;
        this.genres = genres;
        this.popularity = popularity;
    }

    public String getId() { return id; }
    public void setId(String id) { this.id = id; }
    public String getName() { return name; }
    public void setName(String name) { this.name = name; }
    public String getImage() { return image; }
    public void setImage(String image) { this.image = image; }
    public List<String> getGenres() { return genres; }
    public void setGenres(List<String> genres) { this.genres = genres; }
    public int getPopularity() { return popularity; }
    public void setPopularity(int popularity) { this.popularity = popularity; }
}

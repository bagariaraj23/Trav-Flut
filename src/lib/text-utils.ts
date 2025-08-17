export class TextUtils {
  /**
   * Capitalizes the first letter of each word in a string
   */
  static capitalizeWords(input: string): string {
    if (!input) return input;
    
    return input.split(' ').map(word => {
      if (!word) return word;
      return word.charAt(0).toUpperCase() + word.slice(1).toLowerCase();
    }).join(' ');
  }

  /**
   * Capitalizes only the first letter of a string
   */
  static capitalizeFirst(input: string): string {
    if (!input) return input;
    return input.charAt(0).toUpperCase() + input.slice(1);
  }

  /**
   * Formats a name properly (capitalizes each word, trims whitespace)
   */
  static formatName(name: string): string {
    if (!name) return name;
    return this.capitalizeWords(name.trim());
  }

  /**
   * Formats a username (lowercase, no spaces, alphanumeric only)
   */
  static formatUsername(username: string): string {
    if (!username) return username;
    return username.toLowerCase().replace(/[^a-z0-9_]/g, '');
  }

  /**
   * Formats trip title (capitalizes first letter of each word)
   */
  static formatTripTitle(title: string): string {
    if (!title) return title;
    return this.capitalizeWords(title.trim());
  }

  /**
   * Formats location/destination names
   */
  static formatLocation(location: string): string {
    if (!location) return location;
    return this.capitalizeWords(location.trim());
  }

  /**
   * Formats general text content (capitalizes first letter, trims)
   */
  static formatContent(content: string): string {
    if (!content) return content;
    return this.capitalizeFirst(content.trim());
  }

  /**
   * Formats bio text (capitalizes first letter, trims)
   */
  static formatBio(bio: string): string {
    if (!bio) return bio;
    return this.capitalizeFirst(bio.trim());
  }

  /**
   * Formats an array of destinations
   */
  static formatDestinations(destinations: string[]): string[] {
    return destinations.map(dest => this.formatLocation(dest));
  }
}
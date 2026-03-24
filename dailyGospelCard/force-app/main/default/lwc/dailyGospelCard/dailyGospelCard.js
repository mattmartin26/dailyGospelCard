import { LightningElement, track } from 'lwc';
import getTodayGospel from '@salesforce/apex/DailyGospelService.getTodayGospel';

export default class DailyGospelCard extends LightningElement {
  @track isLoading = true;
  @track error;
  @track title;
  @track reference;
  @track body;

  get hasGospel() {
    return !!this.body;
  }

  connectedCallback() {
    this.loadGospel();
  }

  async loadGospel() {
    this.isLoading = true;
    this.error = undefined;
    try {
      const res = await getTodayGospel();
      if (res) {
        this.title = res.title || 'Gospel';
        this.reference = res.reference || '';
        this.body = res.body || '';
      } else {
        this.title = undefined;
        this.reference = undefined;
        this.body = undefined;
      }
    } catch (e) {
      // Prefer user-friendly error
      this.error = (e && e.body && e.body.message) ? e.body.message : 'Unable to load Gospel reading.';
      this.title = undefined;
      this.reference = undefined;
      this.body = undefined;
    } finally {
      this.isLoading = false;
    }
  }
}
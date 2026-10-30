package main

import (
	"encoding/json"
	"testing"
)

func TestMoneyUsesCents(t *testing.T) {
	for _, tc := range []struct {
		usd  float64
		want string
	}{
		{0, "$0.00"}, {0.004, "$0.00"}, {0.009, "$0.01"},
		{0.29, "$0.29"}, {0.9, "$0.90"}, {1.236, "$1.24"}, {12.999, "$13.00"},
	} {
		var payload statuslinePayload
		data, err := json.Marshal(map[string]any{"cost": map[string]float64{"total_cost_usd": tc.usd}})
		if err != nil {
			t.Fatal(err)
		}
		if err := json.Unmarshal(data, &payload); err != nil {
			t.Fatal(err)
		}
		if got := fmtMoney(parseFields(&payload).costCents); got != tc.want {
			t.Errorf("%v: got %q, want %q", tc.usd, got, tc.want)
		}
	}
}

func TestEffortIsColoredLowercaseWithoutIcons(t *testing.T) {
	for level, wantColor := range map[string]string{
		"low": cyan, "medium": blue, "high": yellow, "xhigh": orange, "max": red,
	} {
		glyph, label, color := effortParts(level)
		if glyph != "" || label != level || color != wantColor {
			t.Errorf("%s: got (%q, %q, %q)", level, glyph, label, color)
		}
	}
}
